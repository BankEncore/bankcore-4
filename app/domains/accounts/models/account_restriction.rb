# frozen_string_literal: true

module Accounts
  module Models
    class AccountRestriction < ApplicationRecord
      self.table_name = "account_restrictions"

      TYPE_DEBIT_BLOCK = "debit_block"
      TYPE_FULL_FREEZE = "full_freeze"
      TYPE_CLOSE_BLOCK = "close_block"
      TYPE_WATCH_ONLY = "watch_only"
      RESTRICTION_TYPES = [ TYPE_DEBIT_BLOCK, TYPE_FULL_FREEZE, TYPE_CLOSE_BLOCK, TYPE_WATCH_ONLY ].freeze

      STATUS_ACTIVE = "active"
      STATUS_RELEASED = "released"
      STATUSES = [ STATUS_ACTIVE, STATUS_RELEASED ].freeze

      DEBIT_BLOCKING_TYPES = [ TYPE_DEBIT_BLOCK, TYPE_FULL_FREEZE ].freeze
      CLOSE_BLOCKING_TYPES = [ TYPE_CLOSE_BLOCK, TYPE_DEBIT_BLOCK, TYPE_FULL_FREEZE ].freeze

      belongs_to :deposit_account, class_name: "Accounts::Models::DepositAccount"
      belongs_to :actor, class_name: "Workspace::Models::Operator"
      belongs_to :released_by_actor, class_name: "Workspace::Models::Operator", optional: true
      belongs_to :restricted_operational_event,
        class_name: "Core::OperationalEvents::Models::OperationalEvent",
        optional: true
      belongs_to :unrestricted_operational_event,
        class_name: "Core::OperationalEvents::Models::OperationalEvent",
        optional: true

      validates :restriction_type, presence: true, inclusion: { in: RESTRICTION_TYPES }
      validates :status, presence: true, inclusion: { in: STATUSES }
      validates :channel, presence: true, inclusion: { in: [ "branch" ] }
      validates :idempotency_key, :business_date, :reason_code, :effective_on, presence: true

      scope :active, -> { where(status: STATUS_ACTIVE) }
      scope :debit_blocking, -> { active.where(restriction_type: DEBIT_BLOCKING_TYPES) }
      scope :close_blocking, -> { active.where(restriction_type: CLOSE_BLOCKING_TYPES) }
      scope :full_freeze, -> { active.where(restriction_type: TYPE_FULL_FREEZE) }

      def active?
        status == STATUS_ACTIVE
      end
    end
  end
end
