# frozen_string_literal: true

module Branch
  class ReversalsController < ApplicationController
    before_action :require_reversal_capability!

    def new
      @reversal = default_form_params("branch-reversal")
      @original_event_preview = original_event_preview_for(@reversal)
    end

    def create
      @reversal = reversal_params
      original_event = Core::OperationalEvents::Models::OperationalEvent.find(@reversal[:original_operational_event_id].to_i)
      @original_event_preview = original_event_preview(original_event)
      if original_event.source_account_id.present?
        Accounts::Services::AccountRestrictionPolicy.assert_routine_servicing_allowed!(
          deposit_account_id: original_event.source_account_id
        )
      end
      result = Core::OperationalEvents::Commands::RecordReversal.call(
        original_operational_event_id: @reversal[:original_operational_event_id].to_i,
        channel: branch_channel,
        idempotency_key: @reversal[:idempotency_key],
        actor_id: current_operator.id,
        operating_unit_id: current_operating_unit&.id
      )
      @event = result[:event]
      @outcome = result[:outcome]
      @post_result = post_event_if_requested(@event, @reversal[:record_and_post])
      render :result, status: @outcome == :created ? :created : :ok
    rescue Core::OperationalEvents::Commands::RecordReversal::InvalidRequest,
      Core::OperationalEvents::Commands::RecordReversal::MismatchedIdempotency,
      Core::OperationalEvents::Commands::RecordReversal::PostedReplay,
      Accounts::Commands::AccountRestricted,
      Workspace::Authorization::Forbidden,
      Core::Posting::Commands::PostEvent::InvalidState => e
      @error_message = e.message
      @original_event_preview ||= original_event_preview_for(@reversal || {})
      render :new, status: :unprocessable_entity
    rescue Core::OperationalEvents::Commands::RecordReversal::NotFound => e
      @error_message = e.message
      @original_event_preview ||= original_event_preview_for(@reversal || {})
      render :new, status: :not_found
    end

    private

    def require_reversal_capability!
      require_branch_capability!(Workspace::Authorization::CapabilityRegistry::REVERSAL_CREATE)
    end

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

    def original_event_preview_for(attrs)
      event_id = attrs["original_operational_event_id"] || attrs[:original_operational_event_id]
      return nil if event_id.blank?

      event = Core::OperationalEvents::Models::OperationalEvent.includes(:reversed_by_event, :posting_batches).find_by(id: event_id.to_i)
      return { missing_event_id: event_id } if event.nil?

      original_event_preview(event)
    end

    def original_event_preview(event)
      {
        id: event.id,
        event_type: event.event_type,
        status: event.status,
        amount_minor_units: event.amount_minor_units,
        currency: event.currency,
        source_account_id: event.source_account_id,
        destination_account_id: event.destination_account_id,
        business_date: event.business_date,
        reversed_by_event_id: event.reversed_by_event_id,
        reversal_of_event_id: event.reversal_of_event_id,
        posting_expected: event.posting_batches.any?
      }
    end
  end
end
