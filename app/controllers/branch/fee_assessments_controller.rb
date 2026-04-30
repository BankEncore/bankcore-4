# frozen_string_literal: true

module Branch
  class FeeAssessmentsController < ApplicationController
    before_action :load_account

    def new
      @fee_assessment = default_fee_assessment_params
      @preview = preview_for(@fee_assessment)
    end

    def create
      @fee_assessment = fee_assessment_params
      @preview = preview_for(@fee_assessment)
      Accounts::Services::AccountRestrictionPolicy.assert_routine_servicing_allowed!(deposit_account_id: @account.id)
      result = Core::OperationalEvents::Commands::RecordEvent.call(
        event_type: "fee.assessed",
        channel: branch_channel,
        idempotency_key: @fee_assessment[:idempotency_key],
        amount_minor_units: @fee_assessment[:amount_minor_units].to_i,
        currency: @fee_assessment[:currency],
        source_account_id: @account.id,
        reference_id: @fee_assessment[:reference_id].presence,
        actor_id: current_operator.id,
        operating_unit_id: current_operating_unit&.id
      )
      @event = result[:event]
      @outcome = result[:outcome]
      @post_result = post_event_if_requested(@event, @fee_assessment[:record_and_post])
      render :result, status: @outcome == :created ? :created : :ok
    rescue Core::OperationalEvents::Commands::RecordEvent::InvalidRequest,
      Core::OperationalEvents::Commands::RecordEvent::MismatchedIdempotency,
      Core::OperationalEvents::Commands::RecordEvent::PostedReplay,
      Accounts::Commands::AccountRestricted,
      Core::Posting::Commands::PostEvent::InvalidState => e
      @error_message = e.message
      @preview ||= preview_for(@fee_assessment || {})
      render :new, status: :unprocessable_entity
    rescue Workspace::Authorization::Forbidden => e
      @error_message = e.message
      @preview ||= preview_for(@fee_assessment || {})
      render :new, status: :forbidden
    end

    private

    def load_account
      @account = Accounts::Models::DepositAccount.find(params[:deposit_account_id])
    end

    def default_fee_assessment_params
      {
        "amount_minor_units" => params[:amount_minor_units],
        "currency" => "USD",
        "reference_id" => params[:reference_id],
        "idempotency_key" => default_idempotency_key("branch-fee-assessment"),
        "record_and_post" => "1"
      }
    end

    def fee_assessment_params
      params.require(:fee_assessment).permit(
        :amount_minor_units, :currency, :reference_id, :idempotency_key, :record_and_post
      ).to_h.symbolize_keys
    end

    def preview_for(attrs)
      Teller::Queries::TransactionPreview.call(
        transaction_type: "fee_assessment",
        deposit_account_id: @account.id,
        amount_minor_units: attrs["amount_minor_units"] || attrs[:amount_minor_units],
        currency: attrs["currency"] || attrs[:currency],
        record_and_post: attrs["record_and_post"] || attrs[:record_and_post]
      )
    end
  end
end
