# frozen_string_literal: true

module Accounts
  module Models
    class DepositBalanceRebuildRequest < ApplicationRecord
      self.table_name = "deposit_balance_rebuild_requests"

      REBUILD_TYPE_PROJECTION = "projection"
      REBUILD_TYPES = [ REBUILD_TYPE_PROJECTION ].freeze

      REASON_DRIFT_DETECTED = "drift_detected"
      REASON_FORMULA_VERSION_CHANGE = "formula_version_change"
      REASON_MANUAL_REBUILD = "manual_rebuild"
      REASONS = [
        REASON_DRIFT_DETECTED,
        REASON_FORMULA_VERSION_CHANGE,
        REASON_MANUAL_REBUILD
      ].freeze

      STATUS_REQUESTED = "requested"
      STATUS_COMPLETED = "completed"
      STATUSES = [ STATUS_REQUESTED, STATUS_COMPLETED ].freeze

      belongs_to :deposit_account, class_name: "Accounts::Models::DepositAccount"
      belongs_to :source_operational_event, class_name: "Core::OperationalEvents::Models::OperationalEvent", optional: true

      validates :rebuild_type, presence: true, inclusion: { in: REBUILD_TYPES }
      validates :reason, presence: true, inclusion: { in: REASONS }
      validates :status, presence: true, inclusion: { in: STATUSES }
      validates :requested_at, presence: true
      validates :calculation_version,
        numericality: { only_integer: true, greater_than: 0 }
    end
  end
end
