# frozen_string_literal: true

module Accounts
  module Commands
    class MarkDepositBalanceProjectionStale
      def self.call(
        deposit_account_id:,
        reason: Models::DepositBalanceRebuildRequest::REASON_DRIFT_DETECTED,
        stale_from_date: nil,
        source_operational_event_id: nil,
        expected_calculation_version: Models::DepositAccountBalanceProjection::CURRENT_CALCULATION_VERSION
      )
        new(
          deposit_account_id: deposit_account_id,
          reason: reason,
          stale_from_date: stale_from_date,
          source_operational_event_id: source_operational_event_id,
          expected_calculation_version: expected_calculation_version
        ).call
      end

      def initialize(deposit_account_id:, reason:, stale_from_date:, source_operational_event_id:, expected_calculation_version:)
        @deposit_account_id = deposit_account_id
        @reason = reason
        @stale_from_date = stale_from_date
        @source_operational_event_id = source_operational_event_id
        @expected_calculation_version = expected_calculation_version
      end

      def call
        Models::DepositAccountBalanceProjection.transaction do
          projection = Models::DepositAccountBalanceProjection.lock.find_by(deposit_account_id: deposit_account_id)
          drift = Queries::DepositBalanceProjectionDrift.call(
            deposit_account_id: deposit_account_id,
            expected_calculation_version: expected_calculation_version
          )
          return { projection: projection, drift: drift, rebuild_request: nil } unless drift.drifted

          projection&.update!(
            stale: true,
            stale_from_date: resolved_stale_from_date(projection)
          )

          rebuild_request = Models::DepositBalanceRebuildRequest.create!(
            deposit_account_id: deposit_account_id,
            rebuild_type: Models::DepositBalanceRebuildRequest::REBUILD_TYPE_PROJECTION,
            reason: reason,
            status: Models::DepositBalanceRebuildRequest::STATUS_REQUESTED,
            rebuild_from_date: resolved_stale_from_date(projection),
            source_operational_event_id: source_operational_event_id,
            calculation_version: expected_calculation_version,
            requested_at: Time.current
          )

          { projection: projection&.reload, drift: drift, rebuild_request: rebuild_request }
        end
      end

      private

      attr_reader :deposit_account_id, :reason, :stale_from_date, :source_operational_event_id, :expected_calculation_version

      def resolved_stale_from_date(projection)
        stale_from_date || projection&.as_of_business_date || Core::BusinessDate::Services::CurrentBusinessDate.call
      end
    end
  end
end
