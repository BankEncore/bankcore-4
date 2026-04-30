# frozen_string_literal: true

module Branch
  class FeeWaiversController < ApplicationController
    before_action :require_fee_waive_capability!
    before_action :load_account

    def new
      @fee_waiver = default_fee_waiver_params
      @fee_event = load_fee_event(@fee_waiver["fee_assessment_event_id"])
      @preview = preview_for(@fee_event)
    end

    def create
      @fee_waiver = fee_waiver_params
      @fee_event = load_fee_event(@fee_waiver[:fee_assessment_event_id])
      @preview = preview_for(@fee_event)
      Accounts::Services::AccountRestrictionPolicy.assert_routine_servicing_allowed!(deposit_account_id: @account.id)
      result = Core::OperationalEvents::Commands::RecordEvent.call(
        event_type: "fee.waived",
        channel: branch_channel,
        idempotency_key: @fee_waiver[:idempotency_key],
        amount_minor_units: @fee_event.amount_minor_units,
        currency: @fee_event.currency,
        source_account_id: @account.id,
        reference_id: @fee_event.id.to_s,
        actor_id: current_operator.id,
        operating_unit_id: current_operating_unit&.id
      )
      @event = result[:event]
      @outcome = result[:outcome]
      @post_result = post_event_if_requested(@event, @fee_waiver[:record_and_post])
      render :result, status: @outcome == :created ? :created : :ok
    rescue ActiveRecord::RecordNotFound,
      Core::OperationalEvents::Commands::RecordEvent::InvalidRequest,
      Core::OperationalEvents::Commands::RecordEvent::MismatchedIdempotency,
      Core::OperationalEvents::Commands::RecordEvent::PostedReplay,
      Accounts::Commands::AccountRestricted,
      Core::Posting::Commands::PostEvent::InvalidState => e
      @error_message = e.message
      @preview ||= preview_for(@fee_event) if @fee_event.present?
      render :new, status: :unprocessable_entity
    rescue Workspace::Authorization::Forbidden => e
      @error_message = e.message
      @preview ||= preview_for(@fee_event) if @fee_event.present?
      render :new, status: :forbidden
    end

    private

    def require_fee_waive_capability!
      require_branch_capability!(Workspace::Authorization::CapabilityRegistry::FEE_WAIVE)
    end

    def load_account
      @account = Accounts::Models::DepositAccount.find(params[:deposit_account_id])
    end

    def default_fee_waiver_params
      {
        "fee_assessment_event_id" => params[:fee_assessment_event_id],
        "idempotency_key" => default_idempotency_key("branch-fee-waiver"),
        "record_and_post" => "1"
      }
    end

    def fee_waiver_params
      params.require(:fee_waiver).permit(:fee_assessment_event_id, :idempotency_key, :record_and_post).to_h.symbolize_keys
    end

    def load_fee_event(event_id)
      if event_id.blank?
        raise Core::OperationalEvents::Commands::RecordEvent::InvalidRequest,
          "fee_assessment_event_id is required"
      end

      event = Core::OperationalEvents::Models::OperationalEvent.find(event_id)
      unless event.event_type == "fee.assessed" &&
          event.status == Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED &&
          event.source_account_id == @account.id
        raise Core::OperationalEvents::Commands::RecordEvent::InvalidRequest,
          "fee_assessment_event_id must identify a posted fee.assessed for this account"
      end
      event
    end

    def preview_for(event)
      Teller::Queries::TransactionPreview.call(
        transaction_type: "fee_waiver",
        deposit_account_id: @account.id,
        amount_minor_units: event.amount_minor_units,
        currency: event.currency
      )
    end
  end
end
