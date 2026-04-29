# frozen_string_literal: true

module Cash
  module Models
    class CashVariance < ApplicationRecord
      self.table_name = "cash_variances"

      STATUS_PENDING_APPROVAL = "pending_approval"
      STATUS_APPROVED = "approved"
      STATUS_POSTED = "posted"
      STATUSES = [ STATUS_PENDING_APPROVAL, STATUS_APPROVED, STATUS_POSTED ].freeze

      belongs_to :cash_location, class_name: "Cash::Models::CashLocation"
      belongs_to :cash_count, class_name: "Cash::Models::CashCount"
      belongs_to :operating_unit, class_name: "Organization::Models::OperatingUnit"
      belongs_to :actor, class_name: "Workspace::Models::Operator"
      belongs_to :approving_actor, class_name: "Workspace::Models::Operator", optional: true
      belongs_to :cash_variance_posted_event,
        class_name: "Core::OperationalEvents::Models::OperationalEvent",
        optional: true

      validates :amount_minor_units, numericality: { other_than: 0 }
      validates :currency, inclusion: { in: %w[USD] }
      validates :status, inclusion: { in: STATUSES }
      validates :business_date, presence: true

      def approved_or_posted?
        status == STATUS_APPROVED || status == STATUS_POSTED
      end
    end
  end
end
