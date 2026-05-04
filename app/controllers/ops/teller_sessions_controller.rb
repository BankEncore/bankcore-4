# frozen_string_literal: true

module Ops
  class TellerSessionsController < ApplicationController
    def index
      @sessions = Teller::Models::TellerSession
        .where(status: [
          Teller::Models::TellerSession::STATUS_OPEN,
          Teller::Models::TellerSession::STATUS_PENDING_SUPERVISOR
        ])
        .includes(:operating_unit, :cash_location, :supervisor_operator)
        .order(:opened_at, :id)
    end

    def show
      @session = Teller::Models::TellerSession.includes(:operating_unit, :cash_location, :supervisor_operator).find(params[:id])
      @primary_operator = primary_operator_for_session(@session)
    end

    private

    def primary_operator_for_session(session)
      Core::OperationalEvents::Models::OperationalEvent
        .where(teller_session_id: session.id)
        .where.not(actor_id: nil)
        .includes(:actor)
        .order(:id)
        .first&.actor
    end
  end
end
