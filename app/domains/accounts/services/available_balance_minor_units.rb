# frozen_string_literal: true

module Accounts
  module Services
    # Ledger on 2110 for this deposit account (credits − debits) minus active holds (ADR-0004).
    class AvailableBalanceMinorUnits
      def self.call(deposit_account_id:)
        AvailableBalanceResolver.call(deposit_account_id: deposit_account_id).available_balance_minor_units
      end

      def self.ledger_balance_minor_units(deposit_account_id:)
        AvailableBalanceResolver.journal_ledger_balance_minor_units(deposit_account_id: deposit_account_id)
      end
    end
  end
end
