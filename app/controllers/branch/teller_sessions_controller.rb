# frozen_string_literal: true

module Branch
  class TellerSessionsController < ApplicationController
    def new
      @teller_session = { "drawer_code" => params[:drawer_code] }
    end

    def create
      @teller_session = teller_session_params
      session = Teller::Commands::OpenSession.call(drawer_code: @teller_session[:drawer_code].presence)
      redirect_to branch_path, notice: "Opened teller session ##{session.id}."
    rescue Teller::Commands::OpenSession::SessionAlreadyOpen => e
      @error_message = e.message
      render :new, status: :unprocessable_entity
    end

    def close
      session = Teller::Commands::CloseSession.call(
        teller_session_id: params[:id].to_i,
        expected_cash_minor_units: close_params[:expected_cash_minor_units].to_i,
        actual_cash_minor_units: close_params[:actual_cash_minor_units].to_i
      )
      message = if session.status == Teller::Models::TellerSession::STATUS_PENDING_SUPERVISOR
        "Session ##{session.id} is pending supervisor approval for variance."
      else
        "Closed teller session ##{session.id}."
      end
      redirect_to branch_path, notice: message
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
      params.require(:teller_session_close).permit(:expected_cash_minor_units, :actual_cash_minor_units)
    end
  end
end
