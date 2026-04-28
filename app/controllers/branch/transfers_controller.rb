# frozen_string_literal: true

module Branch
  class TransfersController < ApplicationController
    def new
      @transfer = default_form_params("branch-transfer")
    end

    def create
      @transfer = transfer_params
      result = Accounts::Commands::AuthorizeDebit.call(
        event_type: "transfer.completed",
        channel: "teller",
        idempotency_key: @transfer[:idempotency_key],
        amount_minor_units: @transfer[:amount_minor_units].to_i,
        currency: @transfer[:currency],
        source_account_id: @transfer[:source_account_id].to_i,
        destination_account_id: @transfer[:destination_account_id].to_i,
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
      @post_result = post_event_if_requested(@event, @transfer[:record_and_post])
      render :result, status: @outcome == :created ? :created : :ok
    rescue Accounts::Commands::AuthorizeDebit::InvalidRequest,
      Core::OperationalEvents::Commands::RecordEvent::InvalidRequest,
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
        "source_account_id" => params[:source_account_id],
        "destination_account_id" => params[:destination_account_id],
        "amount_minor_units" => nil,
        "currency" => "USD",
        "idempotency_key" => default_idempotency_key(prefix),
        "record_and_post" => "0"
      }
    end

    def transfer_params
      params.require(:transfer).permit(
        :source_account_id, :destination_account_id, :amount_minor_units, :currency, :idempotency_key, :record_and_post
      ).to_h.symbolize_keys
    end
  end
end
