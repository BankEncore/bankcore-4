# frozen_string_literal: true

module Accounts
  module Models
    class DepositAccountBalanceProjection < ApplicationRecord
      self.table_name = "deposit_account_balance_projections"

      belongs_to :deposit_account, class_name: "Accounts::Models::DepositAccount",
        inverse_of: :deposit_account_balance_projection
      belongs_to :last_journal_entry, class_name: "Core::Ledger::Models::JournalEntry", optional: true
      belongs_to :last_operational_event, class_name: "Core::OperationalEvents::Models::OperationalEvent", optional: true

      validates :deposit_account, presence: true, uniqueness: true
      validates :ledger_balance_minor_units, :available_balance_minor_units,
        numericality: { only_integer: true }
      validates :hold_balance_minor_units,
        numericality: { only_integer: true, greater_than_or_equal_to: 0 }
      validates :collected_balance_minor_units,
        numericality: { only_integer: true },
        allow_nil: true
      validates :calculation_version,
        numericality: { only_integer: true, greater_than: 0 }
    end
  end
end
