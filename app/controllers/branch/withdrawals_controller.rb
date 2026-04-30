# frozen_string_literal: true

module Branch
  class WithdrawalsController < ApplicationController
    def new
      @withdrawal = default_form_params("branch-withdrawal")
      @preview = preview_for(@withdrawal)
    end

    def create
      @withdrawal = withdrawal_params
      @preview = preview_for(@withdrawal)
      result = Accounts::Commands::AuthorizeDebit.call(
        event_type: "withdrawal.posted",
        channel: "teller",
        idempotency_key: @withdrawal[:idempotency_key],
        amount_minor_units: @withdrawal[:amount_minor_units].to_i,
        currency: @withdrawal[:currency],
        source_account_id: @withdrawal[:deposit_account_id].to_i,
        teller_session_id: parse_optional_integer(@withdrawal[:teller_session_id]),
        actor_id: current_operator.id,
        operating_unit_id: current_operating_unit&.id
      )
      if result[:outcome].in?([ Accounts::Commands::AuthorizeDebit::OUTCOME_DENIED, Accounts::Commands::AuthorizeDebit::OUTCOME_DENIED_REPLAY ])
        @outcome = result[:outcome]
        @denial_event = result[:denial_event]
        @fee_event = result[:fee_event]
        render :result, status: :unprocessable_entity
        return
      end

      @event = result[:event]
      @outcome = result[:outcome]
      @post_result = post_event_if_requested(@event, @withdrawal[:record_and_post])
      render :result, status: @outcome == :created ? :created : :ok
    rescue Accounts::Commands::AuthorizeDebit::InvalidRequest,
      Core::OperationalEvents::Commands::RecordEvent::InvalidRequest,
      Core::OperationalEvents::Commands::RecordEvent::MismatchedIdempotency,
      Core::OperationalEvents::Commands::RecordEvent::PostedReplay,
      Core::Posting::Commands::PostEvent::InvalidState => e
      @error_message = e.message
      @preview ||= preview_for(@withdrawal || {})
      render :new, status: :unprocessable_entity
    rescue Core::Posting::Commands::PostEvent::NotFound
      @error_message = "Operational event not found for posting"
      @preview ||= preview_for(@withdrawal || {})
      render :new, status: :not_found
    end

    private

    def default_form_params(prefix)
      {
        "deposit_account_id" => params[:deposit_account_id],
        "amount_minor_units" => params[:amount_minor_units],
        "currency" => "USD",
        "teller_session_id" => params[:teller_session_id],
        "idempotency_key" => default_idempotency_key(prefix),
        "record_and_post" => "0"
      }
    end

    def withdrawal_params
      params.require(:withdrawal).permit(
        :deposit_account_id, :amount_minor_units, :currency, :teller_session_id, :idempotency_key, :record_and_post
      ).to_h.symbolize_keys
    end

    def preview_for(attrs)
      Teller::Queries::TransactionPreview.call(
        transaction_type: "withdrawal",
        deposit_account_id: attrs["deposit_account_id"] || attrs[:deposit_account_id],
        amount_minor_units: attrs["amount_minor_units"] || attrs[:amount_minor_units],
        currency: attrs["currency"] || attrs[:currency],
        teller_session_id: attrs["teller_session_id"] || attrs[:teller_session_id]
      )
    end
  end
end
