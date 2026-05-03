# frozen_string_literal: true

module Accounts
  module Services
    # Projection-backed current balance facade. Journal-derived methods remain explicit for rebuild/reconciliation.
    class AvailableBalanceMinorUnits
      def self.call(deposit_account_id:)
        AvailableBalanceResolver.call(deposit_account_id: deposit_account_id).available_balance_minor_units
      end

      def self.ledger_balance_minor_units(deposit_account_id:)
        AvailableBalanceResolver.call(deposit_account_id: deposit_account_id).ledger_balance_minor_units
      end

      def self.journal_ledger_balance_minor_units(deposit_account_id:)
        AvailableBalanceResolver.journal_ledger_balance_minor_units(deposit_account_id: deposit_account_id)
      end
    end
  end
end
