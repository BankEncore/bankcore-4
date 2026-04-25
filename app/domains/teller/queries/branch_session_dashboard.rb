# frozen_string_literal: true

module Teller
  module Queries
    class BranchSessionDashboard
      Result = Data.define(:open_sessions, :pending_supervisor_sessions, :recent_closed_sessions)

      DEFAULT_LIMIT = 10

      def self.call(limit: DEFAULT_LIMIT)
        new(limit: limit).call
      end

      def initialize(limit:)
        @limit = limit.to_i.clamp(1, 50)
      end

      def call
        Result.new(
          open_sessions: sessions_for(Models::TellerSession::STATUS_OPEN).order(:opened_at, :id).limit(limit).to_a,
          pending_supervisor_sessions: sessions_for(Models::TellerSession::STATUS_PENDING_SUPERVISOR)
            .order(:opened_at, :id)
            .limit(limit)
            .to_a,
          recent_closed_sessions: sessions_for(Models::TellerSession::STATUS_CLOSED)
            .order(closed_at: :desc, id: :desc)
            .limit(limit)
            .to_a
        )
      end

      private

      attr_reader :limit

      def sessions_for(status)
        Models::TellerSession.where(status: status).includes(:supervisor_operator)
      end
    end
  end
end
