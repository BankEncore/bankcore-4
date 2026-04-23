# frozen_string_literal: true

module Accounts
  module Models
    class Hold < ApplicationRecord
      self.table_name = "holds"

      STATUS_ACTIVE = "active"
      STATUS_RELEASED = "released"
      STATUS_EXPIRED = "expired"

      belongs_to :deposit_account, class_name: "Accounts::Models::DepositAccount"
      belongs_to :placed_by_operational_event, class_name: "Core::OperationalEvents::Models::OperationalEvent", optional: true
      belongs_to :released_by_operational_event, class_name: "Core::OperationalEvents::Models::OperationalEvent", optional: true

      scope :active_for_account, ->(deposit_account_id) { where(deposit_account_id: deposit_account_id, status: STATUS_ACTIVE) }
    end
  end
end
