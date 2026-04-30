# frozen_string_literal: true

module Branch
  class CashController < ApplicationController
    before_action -> { require_branch_capability!(Workspace::Authorization::CapabilityRegistry::CASH_POSITION_VIEW) },
      only: [ :index, :show_location ]
    before_action -> { require_branch_capability!(Workspace::Authorization::CapabilityRegistry::CASH_MOVEMENT_CREATE) },
      only: [ :new_transfer, :create_transfer ]
    before_action -> { require_branch_capability!(Workspace::Authorization::CapabilityRegistry::CASH_SHIPMENT_RECEIVE) },
      only: [ :new_external_shipment, :create_external_shipment ]
    before_action -> { require_branch_capability!(Workspace::Authorization::CapabilityRegistry::CASH_COUNT_RECORD) },
      only: [ :new_count, :create_count ]

    def index
      @positions = Cash::Queries::CashPosition.call(operating_unit_id: current_operating_unit&.id)
    end

    def new_transfer
      @locations = active_locations
      @cash_transfer = default_transfer_params
      @preview = transfer_preview_for(@cash_transfer)
    end

    def create_transfer
      @cash_transfer = transfer_params
      @preview = transfer_preview_for(@cash_transfer)
      movement = Cash::Commands::TransferCash.call(
        **@cash_transfer,
        actor_id: current_operator.id,
        channel: branch_channel,
        idempotency_key: @cash_transfer[:idempotency_key].presence || default_idempotency_key("cash-transfer")
      )
      @cash_result_type = "transfer"
      @movement = movement
      render :result, status: :created
    rescue Cash::Commands::TransferCash::Error => e
      @locations = active_locations
      @error_message = e.message
      @preview ||= transfer_preview_for(@cash_transfer || {})
      render :new_transfer, status: :unprocessable_entity
    end

    def new_external_shipment
      @vault_locations = active_vault_locations
      @cash_shipment = {}
    end

    def create_external_shipment
      @cash_shipment = external_shipment_params
      movement = Cash::Commands::ReceiveExternalCashShipment.call(
        **@cash_shipment,
        actor_id: current_operator.id,
        channel: branch_channel,
        idempotency_key: @cash_shipment[:idempotency_key].presence || default_idempotency_key("cash-shipment")
      )
      redirect_to branch_cash_path, notice: "Received external cash shipment ##{movement.id}."
    rescue Cash::Commands::ReceiveExternalCashShipment::Error => e
      @vault_locations = active_vault_locations
      @error_message = e.message
      render :new_external_shipment, status: :unprocessable_entity
    end

    def new_count
      @locations = active_locations
      @cash_count = default_count_params
    end

    def create_count
      @cash_count = count_params
      @cash_count[:expected_amount_minor_units] = nil if @cash_count[:expected_amount_minor_units].blank?
      count = Cash::Commands::RecordCashCount.call(
        **@cash_count,
        actor_id: current_operator.id,
        channel: branch_channel,
        idempotency_key: @cash_count[:idempotency_key].presence || default_idempotency_key("cash-count")
      )
      @cash_result_type = "count"
      @count = count
      render :result, status: :created
    rescue Cash::Commands::RecordCashCount::Error => e
      @locations = active_locations
      @error_message = e.message
      render :new_count, status: :unprocessable_entity
    end

    def show_location
      @activity = Cash::Queries::LocationActivity.call(cash_location_id: params[:id].to_i)
    end

    def approve_movement
      movement = Cash::Models::CashMovement.find(params[:id])
      supervisor = inline_supervisor_operator!(
        approval_params(:cash_movement_approval),
        capability_code: Workspace::Authorization::CapabilityRegistry::CASH_MOVEMENT_APPROVE,
        scope: movement.operating_unit
      )
      approved = Cash::Commands::ApproveCashMovement.call(
        cash_movement_id: movement.id,
        approving_actor_id: supervisor.id,
        channel: branch_channel
      )
      redirect_to branch_path(anchor: "supervisor"), notice: "Approved cash movement ##{approved.id}."
    rescue ActiveRecord::RecordNotFound,
      Cash::Commands::ApproveCashMovement::Error,
      Workspace::Authorization::Forbidden => e
      redirect_to branch_path(anchor: "supervisor"), alert: e.message
    end

    def approve_variance
      variance = Cash::Models::CashVariance.find(params[:id])
      supervisor = inline_supervisor_operator!(
        approval_params(:cash_variance_approval),
        capability_code: Workspace::Authorization::CapabilityRegistry::CASH_VARIANCE_APPROVE,
        scope: variance.operating_unit
      )
      approved = Cash::Commands::ApproveCashVariance.call(
        cash_variance_id: variance.id,
        approving_actor_id: supervisor.id
      )
      redirect_to branch_path(anchor: "supervisor"), notice: "Approved cash variance ##{approved.id}."
    rescue ActiveRecord::RecordNotFound,
      Cash::Commands::ApproveCashVariance::Error,
      Workspace::Authorization::Forbidden => e
      redirect_to branch_path(anchor: "supervisor"), alert: e.message
    end

    private

    def active_locations
      Cash::Models::CashLocation.active.where(operating_unit: current_operating_unit).order(:location_type, :drawer_code, :id)
    end

    def active_vault_locations
      active_locations.where(location_type: Cash::Models::CashLocation::TYPE_BRANCH_VAULT)
    end

    def transfer_params
      params.require(:cash_transfer).permit(
        :source_cash_location_id, :destination_cash_location_id, :amount_minor_units, :idempotency_key, :reason_code
      ).to_h.symbolize_keys
    end

    def default_transfer_params
      {
        "source_cash_location_id" => params[:source_cash_location_id],
        "destination_cash_location_id" => params[:destination_cash_location_id],
        "amount_minor_units" => params[:amount_minor_units],
        "idempotency_key" => default_idempotency_key("cash-transfer"),
        "reason_code" => params[:reason_code]
      }
    end

    def transfer_preview_for(attrs)
      Teller::Queries::TransactionPreview.call(
        transaction_type: "cash_transfer",
        source_cash_location_id: attrs["source_cash_location_id"] || attrs[:source_cash_location_id],
        destination_cash_location_id: attrs["destination_cash_location_id"] || attrs[:destination_cash_location_id],
        amount_minor_units: attrs["amount_minor_units"] || attrs[:amount_minor_units]
      )
    end

    def count_params
      params.require(:cash_count).permit(
        :cash_location_id, :counted_amount_minor_units, :expected_amount_minor_units, :idempotency_key
      ).to_h.symbolize_keys
    end

    def default_count_params
      {
        "cash_location_id" => params[:cash_location_id],
        "counted_amount_minor_units" => params[:counted_amount_minor_units],
        "expected_amount_minor_units" => params[:expected_amount_minor_units],
        "idempotency_key" => default_idempotency_key("cash-count")
      }
    end

    def external_shipment_params
      params.require(:cash_shipment).permit(
        :destination_cash_location_id, :amount_minor_units, :external_source, :shipment_reference, :idempotency_key
      ).to_h.symbolize_keys
    end

    def approval_params(scope)
      params.fetch(scope, ActionController::Parameters.new).permit(
        :supervisor_username, :supervisor_password
      ).to_h.symbolize_keys
    end
  end
end
