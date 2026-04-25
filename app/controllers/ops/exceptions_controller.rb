# frozen_string_literal: true

module Ops
  class ExceptionsController < ApplicationController
    def index
      @pending_events = Core::OperationalEvents::Models::OperationalEvent
        .where(status: Core::OperationalEvents::Models::OperationalEvent::STATUS_PENDING)
        .order(:business_date, :id)
        .limit(50)
      @pending_sessions = Teller::Models::TellerSession
        .where(status: Teller::Models::TellerSession::STATUS_PENDING_SUPERVISOR)
        .order(:opened_at, :id)
      @nsf_denials = Core::OperationalEvents::Models::OperationalEvent
        .where(event_type: "overdraft.nsf_denied")
        .order(id: :desc)
        .limit(25)
    end
  end
end
