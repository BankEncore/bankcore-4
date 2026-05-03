# frozen_string_literal: true

module Reporting
  module Commands
    class MaterializeDailyBalanceSnapshots
      Result = Data.define(:as_of_date, :snapshots_materialized)

      def self.call(as_of_date:, source: Models::DailyBalanceSnapshot::SOURCE_CURRENT_PROJECTION)
        new(as_of_date: as_of_date, source: source).call
      end

      def initialize(as_of_date:, source:)
        @as_of_date = Date.iso8601(as_of_date.to_s)
        @source = source
      end

      def call
        count = 0
        Models::DailyBalanceSnapshot.transaction do
          deposit_projections.find_each do |projection|
            materialize_projection!(projection)
            count += 1
          end
        end

        Result.new(as_of_date: as_of_date, snapshots_materialized: count)
      end

      private

      attr_reader :as_of_date, :source

      def deposit_projections
        Accounts::Models::DepositAccountBalanceProjection.order(:deposit_account_id)
      end

      def materialize_projection!(projection)
        snapshot = Models::DailyBalanceSnapshot.find_or_initialize_by(
          account_domain: Models::DailyBalanceSnapshot::ACCOUNT_DOMAIN_DEPOSITS,
          account_id: projection.deposit_account_id,
          as_of_date: as_of_date
        )
        snapshot.assign_attributes(
          account_type: Models::DailyBalanceSnapshot::ACCOUNT_TYPE_DEPOSIT_ACCOUNT,
          ledger_balance_minor_units: projection.ledger_balance_minor_units,
          hold_balance_minor_units: projection.hold_balance_minor_units,
          available_balance_minor_units: projection.available_balance_minor_units,
          collected_balance_minor_units: projection.collected_balance_minor_units,
          source: source,
          calculation_version: projection.calculation_version
        )
        snapshot.save!
        snapshot
      end
    end
  end
end
