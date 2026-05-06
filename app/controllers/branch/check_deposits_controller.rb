# frozen_string_literal: true

module Branch
  class CheckDepositsController < ApplicationController
    before_action :load_open_teller_sessions, only: %i[new create]

    def new
      @check_deposit = default_form_params("branch-check-deposit")
    end

    def create
      @check_deposit = check_deposit_params
      @check_deposit = normalize_check_deposit_params(@check_deposit)
      account_id = resolve_deposit_account_id(
        @check_deposit[:deposit_account_id],
        @check_deposit[:deposit_account_number]
      )
      payload_items = build_payload_items(@check_deposit[:items])
      amount = payload_items.sum { |item| item.fetch("amount_minor_units") }
      payload = { "items" => payload_items }

      hold_minor = parse_hold_amount_minor_units(@check_deposit)
      hold_idem = resolved_hold_idempotency_key(@check_deposit, hold_minor)

      result = Core::OperationalEvents::Commands::AcceptCheckDeposit.call(
        channel: "teller",
        idempotency_key: @check_deposit[:idempotency_key],
        amount_minor_units: amount,
        currency: @check_deposit[:currency],
        source_account_id: account_id.to_i,
        teller_session_id: parse_optional_integer(@check_deposit[:teller_session_id]),
        actor_id: current_operator.id,
        operating_unit_id: current_operating_unit&.id,
        payload: payload,
        hold_amount_minor_units: hold_minor,
        hold_idempotency_key: hold_idem,
        expires_on: parse_hold_expires_on(@check_deposit[:hold_expires_on])
      )

      @event = result[:operational_event]
      @outcome = result[:record_outcome]
      @post_result = { outcome: result[:posting_outcome] }
      @hold = result[:hold]
      render :result, status: @outcome == :created ? :created : :ok
    rescue Core::OperationalEvents::Commands::AcceptCheckDeposit::InvalidRequest,
      Core::OperationalEvents::Commands::RecordEvent::InvalidRequest,
      Core::OperationalEvents::Commands::RecordEvent::MismatchedIdempotency,
      Core::OperationalEvents::Commands::RecordEvent::PostedReplay,
      Core::Posting::Commands::PostEvent::InvalidState,
      Accounts::Commands::PlaceHold::InvalidRequest,
      ArgumentError,
      ActiveRecord::RecordNotFound => e
      @error_message = e.message
      render :new, status: :unprocessable_entity
    rescue Core::Posting::Commands::PostEvent::NotFound
      @error_message = "Operational event not found for posting"
      render :new, status: :not_found
    end

    private

    def default_form_params(prefix)
      {
        "deposit_account_id" => params[:deposit_account_id],
        "deposit_account_number" => params[:deposit_account_number],
        "amount" => money_amount_display(params[:amount], fallback_minor_units: params[:amount_minor_units]),
        "amount_minor_units" => params[:amount_minor_units],
        "currency" => "USD",
        "teller_session_id" => params[:teller_session_id],
        "idempotency_key" => default_idempotency_key(prefix),
        "items" => [
          {
            "amount" => money_amount_display(params[:amount], fallback_minor_units: params[:amount_minor_units]),
            "amount_minor_units" => params[:amount_minor_units],
            "routing_number" => "",
            "account_number" => "",
            "check_serial_number" => "",
            "classification" => ""
          }
        ],
        "hold_amount" => "",
        "hold_amount_minor_units" => params[:hold_amount_minor_units],
        "hold_idempotency_key" => "",
        "hold_expires_on" => ""
      }
    end

    def check_deposit_params
      params.require(:check_deposit).permit(
        :deposit_account_id, :deposit_account_number, :currency, :teller_session_id,
        :idempotency_key, :hold_amount, :hold_amount_minor_units, :hold_idempotency_key, :hold_expires_on,
        items: %i[amount amount_minor_units routing_number account_number check_serial_number classification]
      ).to_h.symbolize_keys
    end

    def normalize_check_deposit_params(attrs)
      attrs[:currency] = attrs[:currency].presence || "USD"
      attrs[:idempotency_key] = attrs[:idempotency_key].presence || default_idempotency_key("branch-check-deposit")
      attrs[:items] = normalize_check_deposit_items(attrs[:items])

      attrs[:hold_amount] = money_amount_display(
        attrs[:hold_amount],
        fallback_minor_units: attrs[:hold_amount_minor_units]
      )
      attrs
    end

    def normalize_check_deposit_items(raw_items)
      items = Array(raw_items).filter_map do |raw_item|
        item = raw_item.respond_to?(:to_h) ? raw_item.to_h.symbolize_keys : {}
        next if blank_check_deposit_item?(item)

        amount = money_amount_display(item[:amount], fallback_minor_units: item[:amount_minor_units])
        normalized = {
          "amount" => amount,
          "amount_minor_units" => normalize_money_amount_minor_units(
            amount,
            fallback_minor_units: item[:amount_minor_units]
          ),
          "routing_number" => item[:routing_number].to_s.strip,
          "account_number" => item[:account_number].to_s.strip,
          "check_serial_number" => item[:check_serial_number].to_s.strip
        }
        cls = item[:classification].to_s.strip
        normalized["classification"] = cls if %w[on_us transit unknown].include?(cls)
        normalized
      end
      if items.blank?
        raise ArgumentError, "at least one check item is required"
      end

      items
    end

    def blank_check_deposit_item?(item)
      %i[amount amount_minor_units routing_number account_number check_serial_number classification].all? do |key|
        item[key].blank?
      end
    end

    def build_payload_items(items)
      items.map.with_index do |item, idx|
        routing_number = item["routing_number"].to_s.strip
        account_number = item["account_number"].to_s.strip
        check_serial_number = item["check_serial_number"].to_s.strip
        if [ routing_number, account_number, check_serial_number ].any?(&:blank?)
          raise ArgumentError, "check item #{idx + 1} requires routing number, account number, and check serial number"
        end

        payload_item = {
          "amount_minor_units" => item.fetch("amount_minor_units").to_i,
          "routing_number" => routing_number,
          "account_number" => account_number,
          "check_serial_number" => check_serial_number
        }
        payload_item["classification"] = item["classification"] if item["classification"].present?
        payload_item
      end
    end

    def parse_hold_amount_minor_units(attrs)
      display = attrs[:hold_amount].to_s.strip
      return 0 if display.blank? && attrs[:hold_amount_minor_units].blank?

      normalize_money_amount_minor_units(
        display,
        fallback_minor_units: attrs[:hold_amount_minor_units]
      )
    end

    def resolved_hold_idempotency_key(attrs, hold_minor)
      return nil unless hold_minor.positive?

      attrs[:hold_idempotency_key].presence || "#{attrs[:idempotency_key]}-hold"
    end

    def parse_hold_expires_on(raw)
      return nil if raw.blank?

      Date.iso8601(raw.to_s.strip)
    rescue ArgumentError
      raise ArgumentError, "hold release date must be a valid ISO date (YYYY-MM-DD)"
    end

    def load_open_teller_sessions
      @open_teller_sessions = open_teller_sessions_for_branch
    end
  end
end
