# frozen_string_literal: true

module Branch
  class TellerSessionsController < ApplicationController
    before_action -> { require_branch_capability!(Workspace::Authorization::CapabilityRegistry::TELLER_SESSION_VARIANCE_APPROVE, alert: "Teller session variance approval required") },
      only: [ :approve_variance ]

    def new
      @teller_session = { "drawer_code" => params[:drawer_code] }
    end

    def create
      @teller_session = teller_session_params
      session = Teller::Commands::OpenSession.call(
        drawer_code: @teller_session[:drawer_code].presence,
        operator_id: current_operator.id
      )
      redirect_to branch_path, notice: "Opened teller session ##{session.id}."
    rescue Teller::Commands::OpenSession::SessionAlreadyOpen => e
      @error_message = e.message
      render :new, status: :unprocessable_entity
    rescue Organization::Services::ResolveOperatingUnit::Error,
      Organization::Services::DefaultOperatingUnit::AmbiguousDefault,
      Organization::Services::DefaultOperatingUnit::NotFound => e
      @error_message = e.message
      render :new, status: :unprocessable_entity
    end

    def approve_variance
      attrs = approve_variance_params
      teller_session_id = attrs[:teller_session_id].to_i
      session = Teller::Commands::ApproveSessionVariance.call(
        teller_session_id: teller_session_id,
        supervisor_operator_id: current_operator.id
      )
      redirect_to branch_path(anchor: "supervisor"), notice: "Approved variance for teller session ##{session.id}."
    rescue Teller::Commands::ApproveSessionVariance::NotFound => e
      redirect_to branch_path(anchor: "supervisor"), alert: e.message
    rescue Teller::Commands::ApproveSessionVariance::InvalidState => e
      redirect_to branch_path(anchor: "supervisor"), alert: e.message
    end

    def close
      teller_session_id = params[:id].to_i
      session = Teller::Commands::CloseSession.call(
        teller_session_id: teller_session_id,
        expected_cash_minor_units: Teller::Queries::ExpectedCashForSession.call(teller_session_id: teller_session_id),
        actual_cash_minor_units: close_params[:actual_cash_minor_units].to_i
      )
      message = if session.status == Teller::Models::TellerSession::STATUS_PENDING_SUPERVISOR
        "Session ##{session.id} is pending supervisor approval for variance #{session.variance_minor_units} minor units."
      else
        "Closed teller session ##{session.id} with variance #{session.variance_minor_units} minor units."
      end
      anchor = session.status == Teller::Models::TellerSession::STATUS_PENDING_SUPERVISOR ? "supervisor" : "teller"
      redirect_to branch_path(anchor: anchor), notice: message
    rescue Teller::Commands::CloseSession::NotFound => e
      redirect_to branch_path, alert: e.message
    rescue Teller::Commands::CloseSession::InvalidState => e
      redirect_to branch_path, alert: e.message
    end

    private

    def teller_session_params
      params.require(:teller_session).permit(:drawer_code).to_h.symbolize_keys
    end

    def close_params
      params.require(:teller_session_close).permit(:actual_cash_minor_units)
    end

    def approve_variance_params
      params.require(:teller_session_approve_variance).permit(:teller_session_id).to_h.symbolize_keys
    end
  end
end
