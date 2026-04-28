# frozen_string_literal: true

module Branch
  class HoldsController < ApplicationController
    before_action :require_hold_release_capability!, only: %i[release create_release]

    def new
      @hold = default_hold_params("branch-hold")
    end

    def create
      @hold = hold_params
      result = Accounts::Commands::PlaceHold.call(
        deposit_account_id: @hold[:deposit_account_id].to_i,
        amount_minor_units: @hold[:amount_minor_units].to_i,
        currency: @hold[:currency],
        channel: branch_channel,
        idempotency_key: @hold[:idempotency_key],
        placed_for_operational_event_id: parse_optional_integer(@hold[:placed_for_operational_event_id]),
        actor_id: current_operator.id
      )
      @event = result[:event]
      @hold_record = result[:hold]
      @outcome = result[:outcome]
      render :result, status: @outcome == :created ? :created : :ok
    rescue Accounts::Commands::PlaceHold::InvalidRequest => e
      @error_message = e.message
      render :new, status: :unprocessable_entity
    end

    def release
      @hold_release = default_release_params("branch-hold-release")
    end

    def create_release
      @hold_release = release_params
      result = Accounts::Commands::ReleaseHold.call(
        hold_id: @hold_release[:hold_id].to_i,
        channel: branch_channel,
        idempotency_key: @hold_release[:idempotency_key],
        actor_id: current_operator.id
      )
      @event = result[:event]
      @hold_record = result[:hold]
      @outcome = result[:outcome]
      render :result, status: @outcome == :created ? :created : :ok
    rescue Accounts::Commands::ReleaseHold::InvalidRequest,
      Accounts::Commands::ReleaseHold::HoldNotFound => e
      @error_message = e.message
      render :release, status: :unprocessable_entity
    end

    private

    def require_hold_release_capability!
      require_branch_capability!(Workspace::Authorization::CapabilityRegistry::HOLD_RELEASE)
    end

    def default_hold_params(prefix)
      {
        "deposit_account_id" => params[:deposit_account_id],
        "placed_for_operational_event_id" => params[:placed_for_operational_event_id],
        "amount_minor_units" => nil,
        "currency" => "USD",
        "idempotency_key" => default_idempotency_key(prefix)
      }
    end

    def default_release_params(prefix)
      {
        "hold_id" => params[:hold_id],
        "idempotency_key" => default_idempotency_key(prefix)
      }
    end

    def hold_params
      params.require(:hold).permit(
        :deposit_account_id, :placed_for_operational_event_id, :amount_minor_units, :currency, :idempotency_key
      ).to_h.symbolize_keys
    end

    def release_params
      params.require(:hold_release).permit(:hold_id, :idempotency_key).to_h.symbolize_keys
    end
  end
end
