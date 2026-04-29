# frozen_string_literal: true

module Cash
  module Models
    class CashLocation < ApplicationRecord
      self.table_name = "cash_locations"

      TYPE_BRANCH_VAULT = "branch_vault"
      TYPE_TELLER_DRAWER = "teller_drawer"
      TYPE_INTERNAL_TRANSIT = "internal_transit"
      LOCATION_TYPES = [ TYPE_BRANCH_VAULT, TYPE_TELLER_DRAWER, TYPE_INTERNAL_TRANSIT ].freeze

      STATUS_ACTIVE = "active"
      STATUS_INACTIVE = "inactive"
      STATUSES = [ STATUS_ACTIVE, STATUS_INACTIVE ].freeze

      belongs_to :operating_unit, class_name: "Organization::Models::OperatingUnit"
      belongs_to :responsible_operator, class_name: "Workspace::Models::Operator", optional: true
      belongs_to :parent_cash_location, class_name: "Cash::Models::CashLocation", optional: true

      has_many :child_cash_locations, class_name: "Cash::Models::CashLocation",
                                      foreign_key: :parent_cash_location_id,
                                      dependent: :restrict_with_exception
      has_one :cash_balance, class_name: "Cash::Models::CashBalance", dependent: :restrict_with_exception

      validates :location_type, presence: true, inclusion: { in: LOCATION_TYPES }
      validates :status, presence: true, inclusion: { in: STATUSES }
      validates :name, :currency, presence: true
      validates :currency, inclusion: { in: %w[USD] }

      scope :active, -> { where(status: STATUS_ACTIVE) }

      def active?
        status == STATUS_ACTIVE
      end

      def vault?
        location_type == TYPE_BRANCH_VAULT
      end

      def teller_drawer?
        location_type == TYPE_TELLER_DRAWER
      end
    end
  end
end
