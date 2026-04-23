# frozen_string_literal: true

module Teller
  module Queries
    # Composes Core::Ledger aggregates, teller session inventory, and pending operational
    # events for a single business date (institution-wide MVP; see ADR-0016).
    class EodReadiness
      def self.call(business_date:)
        balance = Core::Ledger::Queries::JournalBalanceCheckForBusinessDate.call(business_date: business_date)
        rows = Core::Ledger::Queries::TrialBalanceForBusinessDate.call(business_date: business_date)

        open_count = Teller::Models::TellerSession.where(
          status: [
            Teller::Models::TellerSession::STATUS_OPEN,
            Teller::Models::TellerSession::STATUS_PENDING_SUPERVISOR
          ]
        ).count

        pending_events = Core::OperationalEvents::Models::OperationalEvent.where(
          status: Core::OperationalEvents::Models::OperationalEvent::STATUS_PENDING,
          business_date: business_date
        ).count

        eod_ready = balance.balanced && open_count.zero? && pending_events.zero?

        {
          business_date: business_date.iso8601,
          journal_totals_balanced: balance.balanced,
          total_debit_minor_units: balance.total_debit_minor_units,
          total_credit_minor_units: balance.total_credit_minor_units,
          open_teller_sessions_count: open_count,
          all_sessions_closed: open_count.zero?,
          pending_operational_events_count: pending_events,
          trial_balance_row_count: rows.size,
          eod_ready: eod_ready
        }
      end
    end
  end
end
