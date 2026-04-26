# frozen_string_literal: true

module Accounts
  module Models
    class Hold < ApplicationRecord
      self.table_name = "holds"

      STATUS_ACTIVE = "active"
      STATUS_RELEASED = "released"
      STATUS_EXPIRED = "expired"
      STATUSES = [ STATUS_ACTIVE, STATUS_RELEASED, STATUS_EXPIRED ].freeze

      HOLD_TYPE_ADMINISTRATIVE = "administrative"
      HOLD_TYPE_DEPOSIT = "deposit"
      HOLD_TYPE_LEGAL = "legal"
      HOLD_TYPE_CHANNEL_AUTHORIZATION = "channel_authorization"
      HOLD_TYPES = [
        HOLD_TYPE_ADMINISTRATIVE,
        HOLD_TYPE_DEPOSIT,
        HOLD_TYPE_LEGAL,
        HOLD_TYPE_CHANNEL_AUTHORIZATION
      ].freeze

      REASON_DEPOSIT_AVAILABILITY = "deposit_availability"
      REASON_CUSTOMER_REQUEST = "customer_request"
      REASON_FRAUD_REVIEW = "fraud_review"
      REASON_LEGAL_ORDER = "legal_order"
      REASON_MANUAL_REVIEW = "manual_review"
      REASON_OTHER = "other"
      REASON_CODES = [
        REASON_DEPOSIT_AVAILABILITY,
        REASON_CUSTOMER_REQUEST,
        REASON_FRAUD_REVIEW,
        REASON_LEGAL_ORDER,
        REASON_MANUAL_REVIEW,
        REASON_OTHER
      ].freeze

      CUSTOMER_EXPLANATIONS = {
        REASON_DEPOSIT_AVAILABILITY => "Funds are held while a recent deposit becomes available.",
        REASON_CUSTOMER_REQUEST => "Funds are held at customer request.",
        REASON_FRAUD_REVIEW => "Funds are held while account activity is reviewed.",
        REASON_LEGAL_ORDER => "Funds are restricted due to a legal order.",
        REASON_MANUAL_REVIEW => "Funds are held pending internal review.",
        REASON_OTHER => "Funds are held for another servicing reason recorded by staff."
      }.freeze

      belongs_to :deposit_account, class_name: "Accounts::Models::DepositAccount"
      belongs_to :placed_by_operational_event, class_name: "Core::OperationalEvents::Models::OperationalEvent", optional: true
      belongs_to :released_by_operational_event, class_name: "Core::OperationalEvents::Models::OperationalEvent", optional: true
      belongs_to :placed_for_operational_event, class_name: "Core::OperationalEvents::Models::OperationalEvent", optional: true
      belongs_to :expired_by_operational_event, class_name: "Core::OperationalEvents::Models::OperationalEvent", optional: true

      scope :active_for_account, ->(deposit_account_id) { where(deposit_account_id: deposit_account_id, status: STATUS_ACTIVE) }

      validates :status, presence: true, inclusion: { in: STATUSES }
      validates :hold_type, presence: true, inclusion: { in: HOLD_TYPES }
      validates :reason_code, presence: true, inclusion: { in: REASON_CODES }

      def active?
        status == STATUS_ACTIVE
      end

      def reduces_available_balance?
        active?
      end

      def customer_explanation
        CUSTOMER_EXPLANATIONS.fetch(reason_code)
      end
    end
  end
end
