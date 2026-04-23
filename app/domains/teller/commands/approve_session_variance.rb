# frozen_string_literal: true

module Teller
  module Commands
    class ApproveSessionVariance
      class Error < StandardError; end
      class NotFound < Error; end
      class InvalidState < Error; end

      # @param supervisor_operator_id [Integer, nil] FK to operators; from current_operator in teller workspace.
      def self.call(teller_session_id:, supervisor_operator_id: nil)
        Teller::Models::TellerSession.transaction do
          session = Teller::Models::TellerSession.lock.find_by(id: teller_session_id)
          raise NotFound, "teller_session_id=#{teller_session_id}" if session.nil?

          if session.status == Teller::Models::TellerSession::STATUS_CLOSED &&
              session.supervisor_approved_at.present?
            return session
          end

          unless session.status == Teller::Models::TellerSession::STATUS_PENDING_SUPERVISOR
            raise InvalidState, "session must be pending_supervisor, was #{session.status.inspect}"
          end
          if session.variance_minor_units.nil?
            raise InvalidState, "session has no variance_minor_units recorded"
          end

          session.update!(
            status: Teller::Models::TellerSession::STATUS_CLOSED,
            closed_at: Time.current,
            supervisor_approved_at: Time.current,
            supervisor_operator_id: supervisor_operator_id
          )
          session
        end
      end
    end
  end
end
