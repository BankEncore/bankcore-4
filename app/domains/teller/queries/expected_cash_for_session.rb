# frozen_string_literal: true

module Teller
  module Queries
    class ExpectedCashForSession
      CASH_EVENT_DELTAS = {
        "deposit.accepted" => 1,
        "withdrawal.posted" => -1
      }.freeze
      CASH_MOVEMENT_DELTAS = {
        "vault_to_drawer" => 1,
        "drawer_to_vault" => -1
      }.freeze

      def self.call(teller_session_id:)
        new(teller_session_id: teller_session_id).call
      end

      def initialize(teller_session_id:)
        @teller_session_id = teller_session_id
      end

      def call
        session = Teller::Models::TellerSession.find_by(id: teller_session_id)
        return 0 if session.nil?

        session.opening_cash_minor_units.to_i + teller_event_delta + cash_movement_delta
      end

      private

      attr_reader :teller_session_id

      def teller_event_delta
        Core::OperationalEvents::Models::OperationalEvent
          .where(teller_session_id: teller_session_id, event_type: CASH_EVENT_DELTAS.keys)
          .where(status: Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED)
          .where(reversed_by_event_id: nil)
          .sum { |event| event.amount_minor_units.to_i * CASH_EVENT_DELTAS.fetch(event.event_type) }
      end

      def cash_movement_delta
        Cash::Models::CashMovement
          .where(
            teller_session_id: teller_session_id,
            status: Cash::Models::CashMovement::STATUS_COMPLETED,
            movement_type: CASH_MOVEMENT_DELTAS.keys
          )
          .sum { |movement| movement.amount_minor_units.to_i * CASH_MOVEMENT_DELTAS.fetch(movement.movement_type) }
      end

    end
  end
end
