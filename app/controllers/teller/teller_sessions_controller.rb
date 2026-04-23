# frozen_string_literal: true

module Teller
  class TellerSessionsController < ApplicationController
    def create
      drawer = params.permit(:drawer_code)[:drawer_code]
      session = Teller::Commands::OpenSession.call(drawer_code: drawer)
      render json: { id: session.id, status: session.status, opened_at: session.opened_at }, status: :created
    rescue Teller::Commands::OpenSession::SessionAlreadyOpen => e
      render json: { error: "session_already_open", message: e.message }, status: :unprocessable_entity
    end

    def close
      attrs = params.require(:teller_session_close).permit(
        :teller_session_id, :expected_cash_minor_units, :actual_cash_minor_units
      ).to_h.symbolize_keys
      attrs[:teller_session_id] = attrs[:teller_session_id].to_i
      session = Teller::Commands::CloseSession.call(
        teller_session_id: attrs[:teller_session_id],
        expected_cash_minor_units: attrs[:expected_cash_minor_units].to_i,
        actual_cash_minor_units: attrs[:actual_cash_minor_units].to_i
      )
      render json: { id: session.id, status: session.status, variance_minor_units: session.variance_minor_units }, status: :ok
    rescue Teller::Commands::CloseSession::NotFound => e
      render json: { error: "not_found", message: e.message }, status: :not_found
    rescue Teller::Commands::CloseSession::InvalidState => e
      render json: { error: "invalid_state", message: e.message }, status: :unprocessable_entity
    end
  end
end
