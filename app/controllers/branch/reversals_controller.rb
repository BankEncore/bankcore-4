# frozen_string_literal: true

module Branch
  class ReversalsController < ApplicationController
    before_action :require_branch_supervisor!

    def new
      @reversal = default_form_params("branch-reversal")
    end

    def create
      @reversal = reversal_params
      result = Core::OperationalEvents::Commands::RecordReversal.call(
        original_operational_event_id: @reversal[:original_operational_event_id].to_i,
        channel: "teller",
        idempotency_key: @reversal[:idempotency_key],
        actor_id: current_operator.id
      )
      @event = result[:event]
      @outcome = result[:outcome]
      @post_result = post_event_if_requested(@event, @reversal[:record_and_post])
      render :result, status: @outcome == :created ? :created : :ok
    rescue Core::OperationalEvents::Commands::RecordReversal::InvalidRequest,
      Core::OperationalEvents::Commands::RecordReversal::MismatchedIdempotency,
      Core::OperationalEvents::Commands::RecordReversal::PostedReplay,
      Core::Posting::Commands::PostEvent::InvalidState => e
      @error_message = e.message
      render :new, status: :unprocessable_entity
    rescue Core::OperationalEvents::Commands::RecordReversal::NotFound => e
      @error_message = e.message
      render :new, status: :not_found
    end

    private

    def default_form_params(prefix)
      {
        "original_operational_event_id" => params[:original_operational_event_id],
        "idempotency_key" => default_idempotency_key(prefix),
        "record_and_post" => "0"
      }
    end

    def reversal_params
      params.require(:reversal).permit(:original_operational_event_id, :idempotency_key, :record_and_post).to_h.symbolize_keys
    end
  end
end
