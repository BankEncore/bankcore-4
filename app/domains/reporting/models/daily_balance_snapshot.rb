# frozen_string_literal: true

module Reporting
  module Models
    class DailyBalanceSnapshot < ApplicationRecord
      self.table_name = "daily_balance_snapshots"

      ACCOUNT_DOMAIN_DEPOSITS = "deposits"
      ACCOUNT_TYPE_DEPOSIT_ACCOUNT = "deposit_account"
      SOURCE_CURRENT_PROJECTION = "current_projection"
      ACCOUNT_DOMAINS = [ ACCOUNT_DOMAIN_DEPOSITS ].freeze
      SOURCES = [ SOURCE_CURRENT_PROJECTION ].freeze

      validates :account_domain, :as_of_date, :source, presence: true
      validates :account_domain, inclusion: { in: ACCOUNT_DOMAINS }
      validates :source, inclusion: { in: SOURCES }
      validates :account_id, numericality: { only_integer: true, greater_than: 0 }
      validates :ledger_balance_minor_units, :available_balance_minor_units,
        numericality: { only_integer: true }
      validates :hold_balance_minor_units,
        numericality: { only_integer: true, greater_than_or_equal_to: 0 }
      validates :collected_balance_minor_units,
        numericality: { only_integer: true },
        allow_nil: true
      validates :calculation_version,
        numericality: { only_integer: true, greater_than: 0 }
      validates :account_id,
        uniqueness: { scope: [ :account_domain, :as_of_date ] }
    end
  end
end
