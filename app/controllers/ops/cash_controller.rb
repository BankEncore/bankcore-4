# frozen_string_literal: true

module Ops
  class CashController < ApplicationController
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
  end
end
