# frozen_string_literal: true

module Branch
  class DepositTicketsController < ApplicationController
    before_action :load_open_teller_sessions, only: %i[new create]

    def new
      @deposit_ticket = default_form_params("branch-deposit-ticket")
    end

    def create
      @deposit_ticket = deposit_ticket_params
      @deposit_ticket = normalize_deposit_ticket_params(@deposit_ticket)
      account_id = resolve_deposit_account_id(
        @deposit_ticket[:deposit_account_id],
        @deposit_ticket[:deposit_account_number]
      )
      check_payload_items = build_check_payload_items(@deposit_ticket[:items])
      check_amount = check_payload_items.sum { |item| item.fetch("amount_minor_units") }

      result = Core::OperationalEvents::Commands::AcceptDepositTicket.call(
        channel: "teller",
        idempotency_key: @deposit_ticket[:idempotency_key],
        source_account_id: account_id.to_i,
        currency: @deposit_ticket[:currency],
        teller_session_id: parse_optional_integer(@deposit_ticket[:teller_session_id]),
        actor_id: current_operator.id,
        operating_unit_id: current_operating_unit&.id,
        cash_amount_minor_units: @deposit_ticket[:cash_amount_minor_units],
        check_amount_minor_units: check_amount,
        check_payload: check_payload_items.present? ? { "items" => check_payload_items } : nil,
        hold_amount_minor_units: parse_hold_amount_minor_units(@deposit_ticket),
        hold_idempotency_key: @deposit_ticket[:hold_idempotency_key].presence,
        hold_expires_on: parse_hold_expires_on(@deposit_ticket[:hold_expires_on])
      )

      @ticket_reference = result[:ticket_reference]
      @cash_result = result[:cash_result]
      @check_result = result[:check_result]
      @hold = result[:hold]
      @hold_outcome = result[:hold_outcome]
      render :result, status: :created
    rescue Core::OperationalEvents::Commands::AcceptDepositTicket::InvalidRequest,
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
        "cash_amount" => money_amount_display(params[:cash_amount], fallback_minor_units: params[:cash_amount_minor_units]),
        "cash_amount_minor_units" => params[:cash_amount_minor_units],
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

    def deposit_ticket_params
      params.require(:deposit_ticket).permit(
        :deposit_account_id, :deposit_account_number, :cash_amount, :cash_amount_minor_units, :currency,
        :teller_session_id, :idempotency_key, :hold_amount, :hold_amount_minor_units, :hold_idempotency_key,
        :hold_expires_on,
        items: %i[amount amount_minor_units routing_number account_number check_serial_number classification]
      ).to_h.symbolize_keys
    end

    def normalize_deposit_ticket_params(attrs)
      attrs[:currency] = attrs[:currency].presence || "USD"
      attrs[:idempotency_key] = attrs[:idempotency_key].presence || default_idempotency_key("branch-deposit-ticket")
      attrs[:cash_amount] = money_amount_display(attrs[:cash_amount], fallback_minor_units: attrs[:cash_amount_minor_units])
      attrs[:cash_amount_minor_units] = normalize_optional_money_amount_minor_units(
        attrs[:cash_amount],
        fallback_minor_units: attrs[:cash_amount_minor_units]
      )
      attrs[:items] = normalize_check_items(attrs[:items])
      attrs[:hold_amount] = money_amount_display(
        attrs[:hold_amount],
        fallback_minor_units: attrs[:hold_amount_minor_units]
      )
      attrs
    end

    def normalize_optional_money_amount_minor_units(display_amount, fallback_minor_units: nil)
      return fallback_minor_units.to_i if display_amount.blank? && fallback_minor_units.present?
      return 0 if display_amount.blank?

      normalize_money_amount_minor_units(display_amount, fallback_minor_units: fallback_minor_units)
    end

    def normalize_check_items(raw_items)
      Array(raw_items).filter_map do |raw_item|
        item = raw_item.respond_to?(:to_h) ? raw_item.to_h.symbolize_keys : {}
        next if blank_check_item?(item)

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
    end

    def blank_check_item?(item)
      %i[amount amount_minor_units routing_number account_number check_serial_number classification].all? do |key|
        item[key].blank?
      end
    end

    def build_check_payload_items(items)
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
