# frozen_string_literal: true

module Cash
  module Models
    class CashCount < ApplicationRecord
      self.table_name = "cash_counts"

      STATUS_RECORDED = "recorded"
      STATUSES = [ STATUS_RECORDED ].freeze

      belongs_to :cash_location, class_name: "Cash::Models::CashLocation"
      belongs_to :operating_unit, class_name: "Organization::Models::OperatingUnit"
      belongs_to :actor, class_name: "Workspace::Models::Operator"
      belongs_to :operational_event, class_name: "Core::OperationalEvents::Models::OperationalEvent", optional: true

      has_one :cash_variance, class_name: "Cash::Models::CashVariance", dependent: :restrict_with_exception

      validates :counted_amount_minor_units, :expected_amount_minor_units,
        numericality: { greater_than_or_equal_to: 0 }
      validates :currency, inclusion: { in: %w[USD] }
      validates :status, inclusion: { in: STATUSES }
      validates :business_date, :idempotency_key, :request_fingerprint, presence: true
    end
  end
end
