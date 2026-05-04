# frozen_string_literal: true

module Branch
  class DepositsController < ApplicationController
    before_action :load_open_teller_sessions, only: %i[new create]

    def new
      @deposit = default_form_params("branch-deposit")
      @preview = preview_for(@deposit)
    end

    def create
      @deposit = deposit_params
      @deposit = normalize_deposit_params(@deposit)
      @preview = preview_for(@deposit)
      account_id = resolve_deposit_account_id(@deposit[:deposit_account_id], @deposit[:deposit_account_number])
      result = Core::OperationalEvents::Commands::RecordEvent.call(
        event_type: "deposit.accepted",
        channel: "teller",
        idempotency_key: @deposit[:idempotency_key],
        amount_minor_units: @deposit[:amount_minor_units].to_i,
        currency: @deposit[:currency],
        source_account_id: account_id.to_i,
        teller_session_id: parse_optional_integer(@deposit[:teller_session_id]),
        actor_id: current_operator.id,
        operating_unit_id: current_operating_unit&.id
      )
      @event = result[:event]
      @outcome = result[:outcome]
      @post_result = post_event_if_requested(@event, @deposit[:record_and_post])
      render :result, status: @outcome == :created ? :created : :ok
    rescue Core::OperationalEvents::Commands::RecordEvent::InvalidRequest,
      Core::OperationalEvents::Commands::RecordEvent::MismatchedIdempotency,
      Core::OperationalEvents::Commands::RecordEvent::PostedReplay,
      Core::Posting::Commands::PostEvent::InvalidState,
      ArgumentError,
      ActiveRecord::RecordNotFound => e
      @error_message = e.message
      @preview ||= preview_for(@deposit || {})
      render :new, status: :unprocessable_entity
    rescue Core::Posting::Commands::PostEvent::NotFound
      @error_message = "Operational event not found for posting"
      @preview ||= preview_for(@deposit || {})
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
        "record_and_post" => "0"
      }
    end

    def deposit_params
      params.require(:deposit).permit(
        :deposit_account_id, :deposit_account_number, :amount, :amount_minor_units, :currency, :teller_session_id, :idempotency_key, :record_and_post
      ).to_h.symbolize_keys
    end

    def normalize_deposit_params(attrs)
      attrs[:currency] = attrs[:currency].presence || "USD"
      attrs[:idempotency_key] = attrs[:idempotency_key].presence || default_idempotency_key("branch-deposit")
      attrs[:amount] = money_amount_display(attrs[:amount], fallback_minor_units: attrs[:amount_minor_units])
      attrs[:amount_minor_units] = normalize_money_amount_minor_units(
        attrs[:amount],
        fallback_minor_units: attrs[:amount_minor_units]
      )
      attrs
    end

    def load_open_teller_sessions
      @open_teller_sessions = open_teller_sessions_for_branch
    end

    def preview_for(attrs)
      account_id = lookup_deposit_account_id(
        attrs["deposit_account_id"] || attrs[:deposit_account_id],
        attrs["deposit_account_number"] || attrs[:deposit_account_number]
      )
      Teller::Queries::TransactionPreview.call(
        transaction_type: "deposit",
        deposit_account_id: account_id,
        amount_minor_units: attrs["amount_minor_units"] || attrs[:amount_minor_units],
        currency: attrs["currency"] || attrs[:currency],
        teller_session_id: attrs["teller_session_id"] || attrs[:teller_session_id],
        record_and_post: attrs["record_and_post"] || attrs[:record_and_post]
      )
    end
  end
end
