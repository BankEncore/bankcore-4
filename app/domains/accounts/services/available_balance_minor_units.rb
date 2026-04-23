# frozen_string_literal: true

module Accounts
  module Services
    # Ledger on 2110 for this deposit account (credits − debits) minus active holds (ADR-0004).
    class AvailableBalanceMinorUnits
      GL_DDA = "2110"

      def self.call(deposit_account_id:)
        ledger = ledger_balance_minor_units(deposit_account_id: deposit_account_id)
        held = Accounts::Models::Hold.where(deposit_account_id: deposit_account_id, status: Accounts::Models::Hold::STATUS_ACTIVE)
          .sum(:amount_minor_units)
        ledger - held
      end

      def self.ledger_balance_minor_units(deposit_account_id:)
        dda = Core::Ledger::Models::GlAccount.find_by(account_number: GL_DDA)
        return 0 if dda.nil?

        lines = Core::Ledger::Models::JournalLine.where(gl_account_id: dda.id, deposit_account_id: deposit_account_id)
        credits = lines.where(side: "credit").sum(:amount_minor_units)
        debits = lines.where(side: "debit").sum(:amount_minor_units)
        credits - debits
      end
    end
  end
end
