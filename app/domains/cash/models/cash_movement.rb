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
      TYPE_EXTERNAL_SHIPMENT_RECEIVED = "external_shipment_received"
      MOVEMENT_TYPES = [
        TYPE_VAULT_TO_DRAWER,
        TYPE_DRAWER_TO_VAULT,
        TYPE_INTERNAL_TRANSFER,
        TYPE_ADJUSTMENT,
        TYPE_EXTERNAL_SHIPMENT_RECEIVED
      ].freeze

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
      validates :external_source, :shipment_reference, presence: true, if: :external_shipment_received?

      def completed?
        status == STATUS_COMPLETED
      end

      def pending_approval?
        status == STATUS_PENDING_APPROVAL
      end

      def external_shipment_received?
        movement_type == TYPE_EXTERNAL_SHIPMENT_RECEIVED
      end
    end
  end
end
