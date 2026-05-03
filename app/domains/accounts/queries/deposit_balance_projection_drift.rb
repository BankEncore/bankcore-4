# frozen_string_literal: true

module Accounts
  module Queries
    class DepositBalanceProjectionDrift
      Result = Data.define(
        :deposit_account_id,
        :projection,
        :expected_ledger_balance_minor_units,
        :expected_hold_balance_minor_units,
        :expected_available_balance_minor_units,
        :ledger_balance_drift_minor_units,
        :hold_balance_drift_minor_units,
        :available_balance_drift_minor_units,
        :stale,
        :calculation_version,
        :expected_calculation_version,
        :missing_projection,
        :drifted
      )

      def self.call(deposit_account_id:, expected_calculation_version: Models::DepositAccountBalanceProjection::CURRENT_CALCULATION_VERSION)
        new(
          deposit_account_id: deposit_account_id,
          expected_calculation_version: expected_calculation_version
        ).call
      end

      def initialize(deposit_account_id:, expected_calculation_version:)
        @deposit_account_id = deposit_account_id
        @expected_calculation_version = expected_calculation_version
      end

      def call
        Models::DepositAccount.find(deposit_account_id)

        expected = Services::AvailableBalanceResolver.from_journal(deposit_account_id: deposit_account_id)
        Result.new(
          deposit_account_id: deposit_account_id,
          projection: projection,
          expected_ledger_balance_minor_units: expected.ledger_balance_minor_units,
          expected_hold_balance_minor_units: expected.hold_balance_minor_units,
          expected_available_balance_minor_units: expected.available_balance_minor_units,
          ledger_balance_drift_minor_units: ledger_balance_drift(expected),
          hold_balance_drift_minor_units: hold_balance_drift(expected),
          available_balance_drift_minor_units: available_balance_drift(expected),
          stale: projection&.stale? || false,
          calculation_version: projection&.calculation_version,
          expected_calculation_version: expected_calculation_version,
          missing_projection: projection.nil?,
          drifted: drifted?(expected)
        )
      end

      private

      attr_reader :deposit_account_id, :expected_calculation_version

      def projection
        @projection ||= Models::DepositAccountBalanceProjection.find_by(deposit_account_id: deposit_account_id)
      end

      def ledger_balance_drift(expected)
        return expected.ledger_balance_minor_units if projection.nil?

        projection.ledger_balance_minor_units - expected.ledger_balance_minor_units
      end

      def hold_balance_drift(expected)
        return expected.hold_balance_minor_units if projection.nil?

        projection.hold_balance_minor_units - expected.hold_balance_minor_units
      end

      def available_balance_drift(expected)
        return expected.available_balance_minor_units if projection.nil?

        projection.available_balance_minor_units - expected.available_balance_minor_units
      end

      def drifted?(expected)
        return true if projection.nil?
        return true if projection.stale?
        return true if projection.calculation_version != expected_calculation_version

        ledger_balance_drift(expected) != 0 ||
          hold_balance_drift(expected) != 0 ||
          available_balance_drift(expected) != 0
      end
    end
  end
end
