# frozen_string_literal: true

module Products
  module Models
    class DepositProductOverdraftPolicy < ApplicationRecord
      self.table_name = "deposit_product_overdraft_policies"
      attr_accessor :skip_effective_date_overlap_validation

      MODE_DENY_NSF = "deny_nsf"
      MODES = [ MODE_DENY_NSF ].freeze

      STATUS_ACTIVE = "active"
      STATUS_INACTIVE = "inactive"
      STATUSES = [ STATUS_ACTIVE, STATUS_INACTIVE ].freeze

      belongs_to :deposit_product, class_name: "Products::Models::DepositProduct"

      validates :mode, presence: true, inclusion: { in: MODES }
      validates :nsf_fee_minor_units, numericality: { only_integer: true, greater_than: 0 }
      validates :currency, presence: true
      validates :status, presence: true, inclusion: { in: STATUSES }
      validates :effective_on, presence: true
      validate :ended_on_not_before_effective_on
      validate :currency_matches_deposit_product
      validate :no_overlapping_active_deny_nsf_policy

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

      def no_overlapping_active_deny_nsf_policy
        return if skip_effective_date_overlap_validation
        return unless mode == MODE_DENY_NSF

        return unless Services::EffectiveDatedResolver.overlap?(self, constraints: %i[deposit_product_id mode])

        errors.add(:effective_on, "overlaps an active deny NSF policy for this product")
      end
    end
  end
end
