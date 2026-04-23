# frozen_string_literal: true

module Teller
  module Commands
    class CloseSession
      class Error < StandardError; end
      class NotFound < Error; end
      class InvalidState < Error; end

      def self.call(teller_session_id:, expected_cash_minor_units:, actual_cash_minor_units:)
        Teller::Models::TellerSession.transaction do
          session = Teller::Models::TellerSession.lock.find_by(id: teller_session_id)
          raise NotFound, "teller_session_id=#{teller_session_id}" if session.nil?
          unless session.status == Teller::Models::TellerSession::STATUS_OPEN
            raise InvalidState, "session must be open, was #{session.status.inspect}"
          end

          variance = actual_cash_minor_units.to_i - expected_cash_minor_units.to_i
          session.update!(
            status: Teller::Models::TellerSession::STATUS_CLOSED,
            closed_at: Time.current,
            expected_cash_minor_units: expected_cash_minor_units,
            actual_cash_minor_units: actual_cash_minor_units,
            variance_minor_units: variance
          )
          session
        end
      end
    end
  end
end
