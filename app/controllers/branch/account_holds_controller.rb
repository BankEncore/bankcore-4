# frozen_string_literal: true

module Branch
  class AccountHoldsController < ApplicationController
    before_action :load_account
    before_action :require_branch_supervisor!, only: %i[release create_release]

    def index
      @holds = Accounts::Queries::ListHoldsForAccount.call(
        deposit_account_id: @account.id,
        status: params[:status],
        limit: params[:limit]
      )
    rescue ArgumentError => e
      @error_message = e.message
      @holds = Accounts::Queries::ListHoldsForAccount.call(deposit_account_id: @account.id)
      render :index, status: :unprocessable_entity
    end

    def new
      @hold = default_hold_params("branch-hold")
    end

    def create
      @hold = hold_params.with_indifferent_access
      result = Accounts::Commands::PlaceHold.call(
        deposit_account_id: @account.id,
        amount_minor_units: @hold[:amount_minor_units].to_i,
        currency: @hold[:currency],
        channel: branch_channel,
        idempotency_key: @hold[:idempotency_key],
        placed_for_operational_event_id: parse_optional_integer(@hold[:placed_for_operational_event_id]),
        actor_id: current_operator.id,
        hold_type: @hold[:hold_type],
        reason_code: @hold[:reason_code],
        reason_description: @hold[:reason_description],
        expires_on: @hold[:expires_on]
      )
      render_result(result)
    rescue Accounts::Commands::PlaceHold::InvalidRequest => e
      @error_message = e.message
      render :new, status: :unprocessable_entity
    end

    def release
      @hold_record = Accounts::Models::Hold.includes(:placed_by_operational_event, :placed_for_operational_event).find(params[:hold_id])
      @hold_release = { "idempotency_key" => default_idempotency_key("branch-hold-release") }
    end

    def create_release
      @hold_release = release_params.with_indifferent_access
      result = Accounts::Commands::ReleaseHold.call(
        hold_id: params[:hold_id].to_i,
        channel: branch_channel,
        idempotency_key: @hold_release[:idempotency_key],
        actor_id: current_operator.id
      )
      render_result(result)
    rescue Accounts::Commands::ReleaseHold::InvalidRequest,
      Accounts::Commands::ReleaseHold::HoldNotFound => e
      @error_message = e.message
      @hold_record = Accounts::Models::Hold.find_by(id: params[:hold_id])
      if @hold_record.nil?
        redirect_to branch_account_holds_path(@account), alert: @error_message
        return
      end
      @hold_release = @hold_release.presence || { "idempotency_key" => default_idempotency_key("branch-hold-release") }
      render :release, status: :unprocessable_entity
    end

    private

    def load_account
      @account = Accounts::Models::DepositAccount.find(params[:deposit_account_id])
    end

    def default_hold_params(prefix)
      {
        "placed_for_operational_event_id" => params[:placed_for_operational_event_id],
        "amount_minor_units" => nil,
        "currency" => @account.currency,
        "hold_type" => Accounts::Models::Hold::HOLD_TYPE_ADMINISTRATIVE,
        "reason_code" => Accounts::Models::Hold::REASON_MANUAL_REVIEW,
        "reason_description" => nil,
        "expires_on" => nil,
        "idempotency_key" => default_idempotency_key(prefix)
      }
    end

    def hold_params
      params.require(:hold).permit(
        :placed_for_operational_event_id,
        :amount_minor_units,
        :currency,
        :hold_type,
        :reason_code,
        :reason_description,
        :expires_on,
        :idempotency_key
      ).to_h.symbolize_keys
    end

    def release_params
      params.require(:hold_release).permit(:idempotency_key).to_h.symbolize_keys
    end

    def render_result(result)
      @event = result[:event]
      @hold_record = result[:hold]
      @outcome = result[:outcome]
      render :result, status: @outcome == :created ? :created : :ok
    end
  end
end
