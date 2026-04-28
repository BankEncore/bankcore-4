# frozen_string_literal: true

module Ops
  class TellerVariancesController < ApplicationController
    def index
      @sessions = Teller::Models::TellerSession
        .where(status: Teller::Models::TellerSession::STATUS_PENDING_SUPERVISOR)
        .includes(:supervisor_operator)
        .order(:opened_at, :id)
    end

    def create
      session = Teller::Commands::ApproveSessionVariance.call(
        teller_session_id: params[:id].to_i,
        supervisor_operator_id: current_operator.id
      )
      redirect_to ops_teller_variances_path,
        notice: "Approved variance for teller session ##{session.id}."
    rescue Teller::Commands::ApproveSessionVariance::Error => e
      redirect_to ops_teller_variances_path, alert: e.message
    rescue Workspace::Authorization::Forbidden => e
      redirect_to ops_teller_variances_path, alert: e.message
    end
  end
end
