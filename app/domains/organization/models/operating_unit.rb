# frozen_string_literal: true

module Organization
  module Models
    class OperatingUnit < ApplicationRecord
      self.table_name = "operating_units"

      UNIT_TYPE_INSTITUTION = "institution"
      UNIT_TYPE_BRANCH = "branch"
      UNIT_TYPES = %w[institution branch operations department region].freeze

      STATUS_ACTIVE = "active"
      STATUS_INACTIVE = "inactive"
      STATUS_CLOSED = "closed"
      STATUSES = %w[active inactive closed].freeze

      belongs_to :parent_operating_unit, class_name: "Organization::Models::OperatingUnit", optional: true
      has_many :child_operating_units, class_name: "Organization::Models::OperatingUnit",
                                      foreign_key: :parent_operating_unit_id,
                                      dependent: :restrict_with_exception

      validates :code, presence: true, uniqueness: true
      validates :name, presence: true
      validates :unit_type, presence: true, inclusion: { in: UNIT_TYPES }
      validates :status, presence: true, inclusion: { in: STATUSES }
      validates :time_zone, presence: true
      validate :parent_must_not_be_self
      validate :closed_on_required_for_closed_status

      scope :active, -> { where(status: STATUS_ACTIVE) }
      scope :branches, -> { where(unit_type: UNIT_TYPE_BRANCH) }

      def active?
        status == STATUS_ACTIVE
      end

      private

      def parent_must_not_be_self
        return if id.blank? || parent_operating_unit_id.blank?
        return unless parent_operating_unit_id.to_i == id.to_i

        errors.add(:parent_operating_unit_id, "cannot reference itself")
      end

      def closed_on_required_for_closed_status
        return unless status == STATUS_CLOSED && closed_on.blank?

        errors.add(:closed_on, "is required when status is closed")
      end
    end
  end
end
