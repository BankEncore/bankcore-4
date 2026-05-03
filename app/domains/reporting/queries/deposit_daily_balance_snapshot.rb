# frozen_string_literal: true

module Reporting
  module Queries
    class DepositDailyBalanceSnapshot
      def self.find(deposit_account_id:, as_of_date:)
        Models::DailyBalanceSnapshot.find_by(
          account_domain: Models::DailyBalanceSnapshot::ACCOUNT_DOMAIN_DEPOSITS,
          account_id: deposit_account_id,
          as_of_date: as_of_date.to_date
        )
      end

      def self.ledger_balance_minor_units(deposit_account_id:, as_of_date:)
        find(deposit_account_id: deposit_account_id, as_of_date: as_of_date)&.ledger_balance_minor_units
      end
    end
  end
end
