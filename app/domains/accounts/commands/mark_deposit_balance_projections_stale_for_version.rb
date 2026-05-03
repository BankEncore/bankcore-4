# frozen_string_literal: true

module Accounts
  module Commands
    class MarkDepositBalanceProjectionsStaleForVersion
      Result = Data.define(:expected_calculation_version, :marked_count, :rebuild_requests_created)

      def self.call(expected_calculation_version: Models::DepositAccountBalanceProjection::CURRENT_CALCULATION_VERSION)
        new(expected_calculation_version: expected_calculation_version).call
      end

      def initialize(expected_calculation_version:)
        @expected_calculation_version = expected_calculation_version
      end

      def call
        marked_count = 0
        rebuild_requests_created = 0
        Models::DepositAccountBalanceProjection.transaction do
          stale_scope.find_each do |projection|
            projection.lock!
            projection.update!(
              stale: true,
              stale_from_date: projection.stale_from_date || projection.as_of_business_date || Core::BusinessDate::Services::CurrentBusinessDate.call
            )
            Models::DepositBalanceRebuildRequest.create!(
              deposit_account_id: projection.deposit_account_id,
              rebuild_type: Models::DepositBalanceRebuildRequest::REBUILD_TYPE_PROJECTION,
              reason: Models::DepositBalanceRebuildRequest::REASON_FORMULA_VERSION_CHANGE,
              status: Models::DepositBalanceRebuildRequest::STATUS_REQUESTED,
              rebuild_from_date: projection.stale_from_date,
              calculation_version: expected_calculation_version,
              requested_at: Time.current
            )
            marked_count += 1
            rebuild_requests_created += 1
          end
        end

        Result.new(
          expected_calculation_version: expected_calculation_version,
          marked_count: marked_count,
          rebuild_requests_created: rebuild_requests_created
        )
      end

      private

      attr_reader :expected_calculation_version

      def stale_scope
        Models::DepositAccountBalanceProjection
          .where(stale: false)
          .where.not(calculation_version: expected_calculation_version)
      end
    end
  end
end
