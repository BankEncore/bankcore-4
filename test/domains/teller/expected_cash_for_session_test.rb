# frozen_string_literal: true

require "test_helper"

module Teller
  module Queries
    class ExpectedCashForSessionTest < ActiveSupport::TestCase
      test "sums non-reversed teller cash activity for a session" do
        session = Teller::Models::TellerSession.create!(
          status: Teller::Models::TellerSession::STATUS_OPEN,
          opened_at: Time.current,
          drawer_code: "expected-cash-#{SecureRandom.hex(4)}"
        )
        other_session = Teller::Models::TellerSession.create!(
          status: Teller::Models::TellerSession::STATUS_OPEN,
          opened_at: Time.current,
          drawer_code: "other-cash-#{SecureRandom.hex(4)}"
        )
        reversal = create_event!("posting.reversal", session.id, 200)

        create_event!("deposit.accepted", session.id, 1_000)
        create_event!("withdrawal.posted", session.id, 300)
        create_event!("transfer.completed", session.id, 500)
        create_event!("deposit.accepted", other_session.id, 9_999)
        create_event!("deposit.accepted", session.id, 200, reversed_by_event_id: reversal.id)

        assert_equal 700, ExpectedCashForSession.call(teller_session_id: session.id)
      end

      private

      def create_event!(event_type, teller_session_id, amount_minor_units, reversed_by_event_id: nil)
        Core::OperationalEvents::Models::OperationalEvent.create!(
          event_type: event_type,
          status: Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED,
          business_date: Date.new(2026, 4, 22),
          channel: "teller",
          idempotency_key: "#{event_type}-#{SecureRandom.hex(8)}",
          amount_minor_units: amount_minor_units,
          currency: "USD",
          teller_session_id: teller_session_id,
          reversed_by_event_id: reversed_by_event_id
        )
      end
    end
  end
end
