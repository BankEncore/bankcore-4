# frozen_string_literal: true

module Deposits
  module Queries
    class StatementActivity
      GL_DDA = "2110"

      Result = Data.define(
        :deposit_account,
        :period_start_on,
        :period_end_on,
        :opening_ledger_balance_minor_units,
        :closing_ledger_balance_minor_units,
        :total_debits_minor_units,
        :total_credits_minor_units,
        :line_items
      )

      def self.call(deposit_account_id:, period_start_on:, period_end_on:)
        account = Accounts::Models::DepositAccount.find(deposit_account_id)
        start_on = period_start_on.to_date
        end_on = period_end_on.to_date
        raise ArgumentError, "period_start_on must be on or before period_end_on" if start_on > end_on

        dda = Core::Ledger::Models::GlAccount.find_by(account_number: GL_DDA)
        opening = opening_ledger_balance(dda, account.id, start_on)
        ledger_lines = dda ? ledger_line_items(dda, account.id, start_on, end_on) : []
        no_gl_lines = no_gl_line_items(account.id, start_on, end_on)

        running = opening
        total_debits = 0
        total_credits = 0
        lines = (ledger_lines + no_gl_lines).sort_by { |line| line.fetch(:sort_key) }.map do |line|
          if line.fetch(:affects_ledger)
            amount = line.fetch(:amount_minor_units)
            running += amount
            if amount.negative?
              total_debits += amount.abs
            else
              total_credits += amount
            end
            line[:running_ledger_balance_minor_units] = running
          end
          line.except(:sort_key)
        end

        Result.new(
          deposit_account: account,
          period_start_on: start_on,
          period_end_on: end_on,
          opening_ledger_balance_minor_units: opening,
          closing_ledger_balance_minor_units: closing_ledger_balance(account.id, end_on, running),
          total_debits_minor_units: total_debits,
          total_credits_minor_units: total_credits,
          line_items: lines
        )
      end

      def self.opening_ledger_balance(dda, deposit_account_id, start_on)
        snapshot_balance = Reporting::Queries::DepositDailyBalanceSnapshot.ledger_balance_minor_units(
          deposit_account_id: deposit_account_id,
          as_of_date: start_on - 1.day
        )
        return snapshot_balance unless snapshot_balance.nil?
        return 0 if dda.nil?

        ledger_balance_before(dda, deposit_account_id, start_on)
      end
      private_class_method :opening_ledger_balance

      def self.closing_ledger_balance(deposit_account_id, end_on, running_balance)
        Reporting::Queries::DepositDailyBalanceSnapshot.ledger_balance_minor_units(
          deposit_account_id: deposit_account_id,
          as_of_date: end_on
        ) || running_balance
      end
      private_class_method :closing_ledger_balance

      def self.ledger_balance_before(dda, deposit_account_id, before_date)
        scope = Core::Ledger::Models::JournalLine
          .joins(:journal_entry)
          .where(gl_account_id: dda.id, deposit_account_id: deposit_account_id)
          .where("journal_entries.business_date < ?", before_date)
        credits = scope.where(side: "credit").sum(:amount_minor_units)
        debits = scope.where(side: "debit").sum(:amount_minor_units)
        credits - debits
      end
      private_class_method :ledger_balance_before

      def self.ledger_line_items(dda, deposit_account_id, start_on, end_on)
        Core::Ledger::Models::JournalLine
          .joins(:journal_entry)
          .where(gl_account_id: dda.id, deposit_account_id: deposit_account_id)
          .where(journal_entries: { business_date: start_on..end_on })
          .includes(:gl_account, journal_entry: :operational_event)
          .order(Arel.sql("journal_entries.business_date ASC"), Arel.sql("journal_entries.id ASC"), :sequence_no, :id)
          .map { |line| ledger_line_item(line) }
      end
      private_class_method :ledger_line_items

      def self.ledger_line_item(line)
        entry = line.journal_entry
        event = entry.operational_event
        signed_amount = line.side == "credit" ? line.amount_minor_units : -line.amount_minor_units
        {
          sort_key: [ entry.business_date, entry.id, line.sequence_no, line.id ],
          line_type: "ledger",
          affects_ledger: true,
          business_date: entry.business_date.iso8601,
          event_type: event.event_type,
          operational_event_id: event.id,
          journal_entry_id: entry.id,
          journal_line_id: line.id,
          amount_minor_units: signed_amount,
          currency: entry.currency,
          side: line.side,
          gl_account_number: line.gl_account.account_number,
          source_account_id: event.source_account_id,
          destination_account_id: event.destination_account_id,
          reference_id: event.reference_id,
          reversal_of_event_id: event.reversal_of_event_id,
          reversed_by_event_id: event.reversed_by_event_id,
          running_ledger_balance_minor_units: nil
        }
      end
      private_class_method :ledger_line_item

      def self.no_gl_line_items(deposit_account_id, start_on, end_on)
        Core::OperationalEvents::Models::OperationalEvent
          .where(status: Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED)
          .where(event_type: statement_visible_no_gl_event_types)
          .where(source_account_id: deposit_account_id)
          .where(business_date: start_on..end_on)
          .order(:business_date, :id)
          .map { |event| no_gl_line_item(event) }
      end
      private_class_method :no_gl_line_items

      def self.statement_visible_no_gl_event_types
        Core::OperationalEvents::EventCatalog.statement_visible_no_gl_event_types
      end
      private_class_method :statement_visible_no_gl_event_types

      def self.no_gl_line_item(event)
        {
          sort_key: [ event.business_date, event.id, 0, 0 ],
          line_type: "servicing",
          affects_ledger: false,
          business_date: event.business_date.iso8601,
          event_type: event.event_type,
          operational_event_id: event.id,
          amount_minor_units: event.amount_minor_units,
          currency: event.currency,
          source_account_id: event.source_account_id,
          destination_account_id: event.destination_account_id,
          reference_id: event.reference_id,
          reversal_of_event_id: event.reversal_of_event_id,
          reversed_by_event_id: event.reversed_by_event_id,
          running_ledger_balance_minor_units: nil
        }
      end
      private_class_method :no_gl_line_item
    end
  end
end
