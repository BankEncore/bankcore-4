# frozen_string_literal: true

module Accounts
  module Queries
    class DepositBalanceProjectionHealth
      Result = Data.define(
        :current_calculation_version,
        :total_projection_count,
        :stale_projection_count,
        :projection_version_mismatch_count,
        :pending_rebuild_request_count,
        :completed_rebuild_request_count,
        :stale_daily_snapshot_count,
        :latest_snapshot_date,
        :latest_snapshot_count,
        :recent_rebuild_requests
      )

      def self.call
        new.call
      end

      def call
        Result.new(
          current_calculation_version: current_calculation_version,
          total_projection_count: projection_scope.count,
          stale_projection_count: projection_scope.where(stale: true).count,
          projection_version_mismatch_count: projection_scope.where.not(calculation_version: current_calculation_version).count,
          pending_rebuild_request_count: rebuild_scope.where(status: Models::DepositBalanceRebuildRequest::STATUS_REQUESTED).count,
          completed_rebuild_request_count: rebuild_scope.where(status: Models::DepositBalanceRebuildRequest::STATUS_COMPLETED).count,
          stale_daily_snapshot_count: daily_snapshot_scope.where(stale: true).count,
          latest_snapshot_date: latest_snapshot_date,
          latest_snapshot_count: latest_snapshot_count,
          recent_rebuild_requests: recent_rebuild_requests
        )
      end

      private

      def current_calculation_version
        Models::DepositAccountBalanceProjection::CURRENT_CALCULATION_VERSION
      end

      def projection_scope
        Models::DepositAccountBalanceProjection
      end

      def rebuild_scope
        Models::DepositBalanceRebuildRequest
      end

      def daily_snapshot_scope
        Reporting::Models::DailyBalanceSnapshot.where(
          account_domain: Reporting::Models::DailyBalanceSnapshot::ACCOUNT_DOMAIN_DEPOSITS
        )
      end

      def latest_snapshot_date
        @latest_snapshot_date ||= daily_snapshot_scope.maximum(:as_of_date)
      end

      def latest_snapshot_count
        return 0 if latest_snapshot_date.nil?

        daily_snapshot_scope.where(as_of_date: latest_snapshot_date).count
      end

      def recent_rebuild_requests
        rebuild_scope
          .includes(:deposit_account)
          .order(requested_at: :desc, id: :desc)
          .limit(10)
      end
    end
  end
end
