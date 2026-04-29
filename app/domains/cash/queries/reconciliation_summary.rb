# frozen_string_literal: true

module Cash
  module Queries
    module ReconciliationSummary
      module_function

      def call(operating_unit_id: nil, business_date: nil)
        cash_scope = Cash::Models::CashLocation.joins(:cash_balance)
        cash_scope = cash_scope.where(operating_unit_id: operating_unit_id) if operating_unit_id.present?
        subledger_amount = cash_scope.sum("cash_balances.amount_minor_units").to_i

        journal_lines = Core::Ledger::Models::JournalLine
          .joins(:gl_account, :journal_entry)
          .where(gl_accounts: { account_number: "1110" })
        journal_lines = journal_lines.where(journal_entries: { business_date: business_date }) if business_date.present?
        gl_amount = journal_lines.sum(
          "CASE WHEN journal_lines.side = 'debit' THEN journal_lines.amount_minor_units ELSE -journal_lines.amount_minor_units END"
        ).to_i

        {
          operating_unit_id: operating_unit_id,
          business_date: business_date,
          cash_subledger_amount_minor_units: subledger_amount,
          gl_1110_amount_minor_units: gl_amount,
          difference_minor_units: subledger_amount - gl_amount
        }
      end
    end
  end
end
