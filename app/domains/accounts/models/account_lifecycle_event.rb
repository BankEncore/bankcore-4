# frozen_string_literal: true

module Accounts
  module Models
    class AccountLifecycleEvent < ApplicationRecord
      self.table_name = "account_lifecycle_events"

      ACTION_CLOSED = "closed"
      ACTIONS = [ ACTION_CLOSED ].freeze

      belongs_to :deposit_account, class_name: "Accounts::Models::DepositAccount"
      belongs_to :actor, class_name: "Workspace::Models::Operator"
      belongs_to :operational_event, class_name: "Core::OperationalEvents::Models::OperationalEvent", optional: true

      validates :action, presence: true, inclusion: { in: ACTIONS }
      validates :channel, presence: true, inclusion: { in: [ "branch" ] }
      validates :idempotency_key, :business_date, :reason_code, :effective_on, presence: true
    end
  end
end
