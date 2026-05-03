# frozen_string_literal: true

module Reporting
  module Commands
    class MaterializeDailyBalanceSnapshots
      class ProjectionDriftDetected < StandardError
        attr_reader :drift

        def initialize(drift)
          @drift = drift
          super("deposit balance projection drift detected for deposit_account_id=#{drift.deposit_account_id}")
        end
      end

      Result = Data.define(:as_of_date, :snapshots_materialized)

      def self.call(
        as_of_date:,
        source: Models::DailyBalanceSnapshot::SOURCE_CURRENT_PROJECTION,
        expected_calculation_version: Accounts::Models::DepositAccountBalanceProjection::CURRENT_CALCULATION_VERSION
      )
        new(as_of_date: as_of_date, source: source, expected_calculation_version: expected_calculation_version).call
      end

      def initialize(as_of_date:, source:, expected_calculation_version:)
        @as_of_date = Date.iso8601(as_of_date.to_s)
        @source = source
        @expected_calculation_version = expected_calculation_version
      end

      def call
        count = 0
        Models::DailyBalanceSnapshot.transaction do
          deposit_accounts.find_each do |account|
            projection = projection_for(account)
            assert_projection_current!(account)
            materialize_projection!(projection.reload)
            count += 1
          end
        end

        Result.new(as_of_date: as_of_date, snapshots_materialized: count)
      end

      private

      attr_reader :as_of_date, :source, :expected_calculation_version

      def deposit_accounts
        Accounts::Models::DepositAccount
          .where(status: Accounts::Models::DepositAccount::STATUS_OPEN)
          .order(:id)
      end

      def projection_for(account)
        account.deposit_account_balance_projection ||
          Accounts::Commands::RebuildDepositBalanceProjection.call(deposit_account_id: account.id)
      end

      def assert_projection_current!(account)
        drift = Accounts::Queries::DepositBalanceProjectionDrift.call(
          deposit_account_id: account.id,
          expected_calculation_version: expected_calculation_version
        )
        raise ProjectionDriftDetected, drift if drift.drifted
      end

      def materialize_projection!(projection)
        snapshot = Models::DailyBalanceSnapshot.find_or_initialize_by(
          account_domain: Models::DailyBalanceSnapshot::ACCOUNT_DOMAIN_DEPOSITS,
          account_id: projection.deposit_account_id,
          as_of_date: as_of_date,
          source: source,
          calculation_version: projection.calculation_version
        )
        snapshot.assign_attributes(
          account_type: Models::DailyBalanceSnapshot::ACCOUNT_TYPE_DEPOSIT_ACCOUNT,
          ledger_balance_minor_units: projection.ledger_balance_minor_units,
          hold_balance_minor_units: projection.hold_balance_minor_units,
          available_balance_minor_units: projection.available_balance_minor_units,
          collected_balance_minor_units: projection.collected_balance_minor_units,
          stale: false,
          stale_from_date: nil
        )
        snapshot.save!
        snapshot
      end
    end
  end
end
