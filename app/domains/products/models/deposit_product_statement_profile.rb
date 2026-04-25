# frozen_string_literal: true

module Products
  module Models
    class DepositProductStatementProfile < ApplicationRecord
      self.table_name = "deposit_product_statement_profiles"
      attr_accessor :skip_effective_date_overlap_validation

      FREQUENCY_MONTHLY = "monthly"
      FREQUENCIES = [ FREQUENCY_MONTHLY ].freeze

      STATUS_ACTIVE = "active"
      STATUS_INACTIVE = "inactive"
      STATUSES = [ STATUS_ACTIVE, STATUS_INACTIVE ].freeze

      belongs_to :deposit_product, class_name: "Products::Models::DepositProduct"
      has_many :deposit_statements, class_name: "Deposits::Models::DepositStatement",
                                    inverse_of: :deposit_product_statement_profile,
                                    dependent: :restrict_with_exception

      validates :frequency, presence: true, inclusion: { in: FREQUENCIES }
      validates :cycle_day, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 31 }
      validates :currency, presence: true
      validates :status, presence: true, inclusion: { in: STATUSES }
      validates :effective_on, presence: true
      validate :ended_on_not_before_effective_on
      validate :currency_matches_deposit_product
      validate :no_overlapping_active_monthly_profile

      private

      def ended_on_not_before_effective_on
        return if ended_on.blank? || effective_on.blank?
        return if ended_on >= effective_on

        errors.add(:ended_on, "must be on or after effective_on")
      end

      def currency_matches_deposit_product
        return if deposit_product.nil?
        return if currency == deposit_product.currency

        errors.add(:currency, "must match deposit product currency")
      end

      def no_overlapping_active_monthly_profile
        return if skip_effective_date_overlap_validation
        return unless frequency == FREQUENCY_MONTHLY

        return unless Services::EffectiveDatedResolver.overlap?(self, constraints: %i[deposit_product_id frequency])

        errors.add(:effective_on, "overlaps an active monthly statement profile for this product")
      end
    end
  end
end
