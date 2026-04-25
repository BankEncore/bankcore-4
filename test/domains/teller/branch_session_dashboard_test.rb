# frozen_string_literal: true

require "test_helper"

module Teller
  module Queries
    class BranchSessionDashboardTest < ActiveSupport::TestCase
      test "groups sessions by dashboard status and orders them" do
        open_later = create_session!(status: "open", opened_at: Time.zone.parse("2026-04-24 10:00"))
        open_earlier = create_session!(status: "open", opened_at: Time.zone.parse("2026-04-24 09:00"))
        pending_earlier = create_session!(status: "pending_supervisor", opened_at: Time.zone.parse("2026-04-24 08:00"))
        pending_later = create_session!(status: "pending_supervisor", opened_at: Time.zone.parse("2026-04-24 11:00"))
        closed_older = create_session!(
          status: "closed",
          opened_at: Time.zone.parse("2026-04-24 06:00"),
          closed_at: Time.zone.parse("2026-04-24 07:00")
        )
        closed_newer = create_session!(
          status: "closed",
          opened_at: Time.zone.parse("2026-04-24 12:00"),
          closed_at: Time.zone.parse("2026-04-24 13:00")
        )

        result = BranchSessionDashboard.call

        assert_equal [ open_earlier, open_later ], result.open_sessions
        assert_equal [ pending_earlier, pending_later ], result.pending_supervisor_sessions
        assert_equal [ closed_newer, closed_older ], result.recent_closed_sessions
      end

      test "limits each dashboard group" do
        3.times do |i|
          create_session!(status: "open", opened_at: Time.zone.parse("2026-04-24 09:0#{i}"))
          create_session!(status: "pending_supervisor", opened_at: Time.zone.parse("2026-04-24 10:0#{i}"))
          create_session!(
            status: "closed",
            opened_at: Time.zone.parse("2026-04-24 11:0#{i}"),
            closed_at: Time.zone.parse("2026-04-24 12:0#{i}")
          )
        end

        result = BranchSessionDashboard.call(limit: 2)

        assert_equal 2, result.open_sessions.size
        assert_equal 2, result.pending_supervisor_sessions.size
        assert_equal 2, result.recent_closed_sessions.size
      end

      private

      def create_session!(**attrs)
        Teller::Models::TellerSession.create!(
          {
            status: attrs.fetch(:status),
            opened_at: attrs.fetch(:opened_at),
            drawer_code: "drawer-#{SecureRandom.hex(4)}",
            expected_cash_minor_units: 10_000,
            actual_cash_minor_units: 10_500,
            variance_minor_units: 500
          }.merge(attrs)
        )
      end
    end
  end
end
