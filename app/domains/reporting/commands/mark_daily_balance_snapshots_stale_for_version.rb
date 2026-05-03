# frozen_string_literal: true

module Reporting
  module Commands
    class MarkDailyBalanceSnapshotsStaleForVersion
      Result = Data.define(:expected_calculation_version, :marked_count)

      def self.call(expected_calculation_version: Accounts::Models::DepositAccountBalanceProjection::CURRENT_CALCULATION_VERSION)
        new(expected_calculation_version: expected_calculation_version).call
      end

      def initialize(expected_calculation_version:)
        @expected_calculation_version = expected_calculation_version
      end

      def call
        count = stale_scope.update_all(
          stale: true,
          stale_from_date: Arel.sql("as_of_date"),
          updated_at: Time.current
        )

        Result.new(expected_calculation_version: expected_calculation_version, marked_count: count)
      end

      private

      attr_reader :expected_calculation_version

      def stale_scope
        Models::DailyBalanceSnapshot
          .where(stale: false)
          .where.not(calculation_version: expected_calculation_version)
      end
    end
  end
end
