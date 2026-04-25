# frozen_string_literal: true

module Branch
  class DepositsController < ApplicationController
    def new
      @deposit = default_form_params("branch-deposit")
    end

    def create
      @deposit = deposit_params
      result = Core::OperationalEvents::Commands::RecordEvent.call(
        event_type: "deposit.accepted",
        channel: "teller",
        idempotency_key: @deposit[:idempotency_key],
        amount_minor_units: @deposit[:amount_minor_units].to_i,
        currency: @deposit[:currency],
        source_account_id: @deposit[:deposit_account_id].to_i,
        teller_session_id: parse_optional_integer(@deposit[:teller_session_id]),
        actor_id: current_operator.id
      )
      @event = result[:event]
      @outcome = result[:outcome]
      @post_result = post_event_if_requested(@event, @deposit[:record_and_post])
      render :result, status: @outcome == :created ? :created : :ok
    rescue Core::OperationalEvents::Commands::RecordEvent::InvalidRequest,
      Core::OperationalEvents::Commands::RecordEvent::MismatchedIdempotency,
      Core::OperationalEvents::Commands::RecordEvent::PostedReplay,
      Core::Posting::Commands::PostEvent::InvalidState => e
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
        "amount_minor_units" => nil,
        "currency" => "USD",
        "teller_session_id" => params[:teller_session_id],
        "idempotency_key" => default_idempotency_key(prefix),
        "record_and_post" => "0"
      }
    end

    def deposit_params
      params.require(:deposit).permit(
        :deposit_account_id, :amount_minor_units, :currency, :teller_session_id, :idempotency_key, :record_and_post
      ).to_h.symbolize_keys
    end
  end
end
