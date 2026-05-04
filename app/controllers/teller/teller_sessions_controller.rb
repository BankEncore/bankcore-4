# frozen_string_literal: true

module Teller
  class TellerSessionsController < ApplicationController
    before_action :require_variance_approval_capability!, only: [ :approve_variance ]

    def create
      attrs = params.permit(:drawer_code, :operating_unit_id)
      session = Teller::Commands::OpenSession.call(
        drawer_code: attrs[:drawer_code],
        operator_id: current_operator.id,
        operating_unit_id: attrs[:operating_unit_id]
      )
      render json: {
        id: session.id,
        status: session.status,
        opened_at: session.opened_at,
        operating_unit_id: session.operating_unit_id,
        cash_location_id: session.cash_location_id
      }, status: :created
    rescue Teller::Commands::OpenSession::SessionAlreadyOpen => e
      render json: { error: "session_already_open", message: e.message }, status: :unprocessable_entity
    rescue Organization::Services::ResolveOperatingUnit::Error,
      Organization::Services::DefaultOperatingUnit::AmbiguousDefault,
      Organization::Services::DefaultOperatingUnit::NotFound => e
      render json: { error: "invalid_operating_unit", message: e.message }, status: :unprocessable_entity
    end

    def close
      attrs = params.require(:teller_session_close).permit(
        :teller_session_id, :actual_cash_minor_units
      ).to_h.symbolize_keys
      attrs[:teller_session_id] = attrs[:teller_session_id].to_i
      session = Teller::Commands::CloseSession.call(
        teller_session_id: attrs[:teller_session_id],
        actual_cash_minor_units: attrs[:actual_cash_minor_units].to_i
      )
      render json: { id: session.id, status: session.status, variance_minor_units: session.variance_minor_units }, status: :ok
    rescue Teller::Commands::CloseSession::NotFound => e
      render json: { error: "not_found", message: e.message }, status: :not_found
    rescue Teller::Commands::CloseSession::InvalidState => e
      render json: { error: "invalid_state", message: e.message }, status: :unprocessable_entity
    end

    def approve_variance
      attrs = params.require(:teller_session_approve_variance).permit(:teller_session_id).to_h.symbolize_keys
      teller_session_id = attrs[:teller_session_id].to_i
      session = Teller::Commands::ApproveSessionVariance.call(
        teller_session_id: teller_session_id,
        supervisor_operator_id: current_operator.id
      )
      render json: {
        id: session.id,
        status: session.status,
        variance_minor_units: session.variance_minor_units,
        supervisor_approved_at: session.supervisor_approved_at,
        supervisor_operator_id: session.supervisor_operator_id
      }, status: :ok
    rescue Teller::Commands::ApproveSessionVariance::NotFound => e
      render json: { error: "not_found", message: e.message }, status: :not_found
    rescue Teller::Commands::ApproveSessionVariance::InvalidState => e
      render json: { error: "invalid_state", message: e.message }, status: :unprocessable_entity
    rescue Workspace::Authorization::Forbidden
      render json: { error: "forbidden", message: "supervisor role required" }, status: :forbidden
    end

    private

    def require_variance_approval_capability!
      require_capability!(Workspace::Authorization::CapabilityRegistry::TELLER_SESSION_VARIANCE_APPROVE)
    end
  end
end
