# frozen_string_literal: true

module Teller
  module Queries
    class ExpectedCashForSession
      CASH_EVENT_DELTAS = {
        "deposit.accepted" => 1,
        "withdrawal.posted" => -1
      }.freeze

      def self.call(teller_session_id:)
        new(teller_session_id: teller_session_id).call
      end

      def initialize(teller_session_id:)
        @teller_session_id = teller_session_id
      end

      def call
        Core::OperationalEvents::Models::OperationalEvent
          .where(teller_session_id: teller_session_id, event_type: CASH_EVENT_DELTAS.keys)
          .where(reversed_by_event_id: nil)
          .sum { |event| event.amount_minor_units.to_i * CASH_EVENT_DELTAS.fetch(event.event_type) }
      end

      private

      attr_reader :teller_session_id
    end
  end
end
