# frozen_string_literal: true

module Ops
  class CashController < ApplicationController
    before_action :require_current_operating_unit!
    before_action :require_cash_position_view!, only: %i[index reconciliation]
    before_action :require_cash_movement_approval!, only: :approve_movement
    before_action :require_cash_variance_approval!, only: :approve_variance

    def index
      @approvals = Cash::Queries::PendingCashApprovals.call(operating_unit_id: current_operating_unit&.id)
      @summary = Cash::Queries::ReconciliationSummary.call(operating_unit_id: current_operating_unit&.id)
    end

    def approve_movement
      movement = Cash::Commands::ApproveCashMovement.call(
        cash_movement_id: params[:id].to_i,
        approving_actor_id: current_operator.id,
        channel: "branch"
      )
      redirect_to ops_cash_path, notice: "Approved cash movement ##{movement.id}."
    rescue Cash::Commands::ApproveCashMovement::Error => e
      redirect_to ops_cash_path, alert: e.message
    end

    def approve_variance
      variance = Cash::Commands::ApproveCashVariance.call(
        cash_variance_id: params[:id].to_i,
        approving_actor_id: current_operator.id
      )
      redirect_to ops_cash_path, notice: "Approved cash variance ##{variance.id}."
    rescue Cash::Commands::ApproveCashVariance::Error => e
      redirect_to ops_cash_path, alert: e.message
    end

    def reconciliation
      @summary = Cash::Queries::ReconciliationSummary.call(
        operating_unit_id: current_operating_unit&.id,
        business_date: params[:business_date].presence
      )
    end

    private

    def require_cash_position_view!
      require_cash_capability!(
        Workspace::Authorization::CapabilityRegistry::CASH_POSITION_VIEW,
        current_operating_unit
      )
    end

    def require_cash_movement_approval!
      movement = Cash::Models::CashMovement.find_by(id: params[:id].to_i)
      return if movement.nil?

      require_cash_capability!(
        Workspace::Authorization::CapabilityRegistry::CASH_MOVEMENT_APPROVE,
        movement.operating_unit
      )
    end

    def require_cash_variance_approval!
      variance = Cash::Models::CashVariance.find_by(id: params[:id].to_i)
      return if variance.nil?

      require_cash_capability!(
        Workspace::Authorization::CapabilityRegistry::CASH_VARIANCE_APPROVE,
        variance.operating_unit
      )
    end

    def require_cash_capability!(capability_code, operating_unit)
      return if current_operator&.has_capability?(capability_code, scope: operating_unit)

      render plain: "Forbidden", status: :forbidden
    end
  end
end
