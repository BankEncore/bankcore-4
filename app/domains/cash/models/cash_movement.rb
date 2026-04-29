# frozen_string_literal: true

module Cash
  module Models
    class CashMovement < ApplicationRecord
      self.table_name = "cash_movements"

      STATUS_PENDING_APPROVAL = "pending_approval"
      STATUS_APPROVED = "approved"
      STATUS_COMPLETED = "completed"
      STATUS_CANCELLED = "cancelled"
      STATUS_REJECTED = "rejected"
      STATUSES = [
        STATUS_PENDING_APPROVAL,
        STATUS_APPROVED,
        STATUS_COMPLETED,
        STATUS_CANCELLED,
        STATUS_REJECTED
      ].freeze

      TYPE_VAULT_TO_DRAWER = "vault_to_drawer"
      TYPE_DRAWER_TO_VAULT = "drawer_to_vault"
      TYPE_INTERNAL_TRANSFER = "internal_transfer"
      TYPE_ADJUSTMENT = "adjustment"
      MOVEMENT_TYPES = [ TYPE_VAULT_TO_DRAWER, TYPE_DRAWER_TO_VAULT, TYPE_INTERNAL_TRANSFER, TYPE_ADJUSTMENT ].freeze

      belongs_to :source_cash_location, class_name: "Cash::Models::CashLocation", optional: true
      belongs_to :destination_cash_location, class_name: "Cash::Models::CashLocation", optional: true
      belongs_to :operating_unit, class_name: "Organization::Models::OperatingUnit"
      belongs_to :actor, class_name: "Workspace::Models::Operator"
      belongs_to :approving_actor, class_name: "Workspace::Models::Operator", optional: true
      belongs_to :operational_event, class_name: "Core::OperationalEvents::Models::OperationalEvent", optional: true

      validates :amount_minor_units, numericality: { greater_than: 0 }
      validates :currency, inclusion: { in: %w[USD] }
      validates :status, inclusion: { in: STATUSES }
      validates :movement_type, inclusion: { in: MOVEMENT_TYPES }
      validates :business_date, :idempotency_key, :request_fingerprint, presence: true

      def completed?
        status == STATUS_COMPLETED
      end

      def pending_approval?
        status == STATUS_PENDING_APPROVAL
      end
    end
  end
end
