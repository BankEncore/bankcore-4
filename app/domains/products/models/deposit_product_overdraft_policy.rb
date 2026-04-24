# frozen_string_literal: true

module Products
  module Models
    class DepositProductOverdraftPolicy < ApplicationRecord
      self.table_name = "deposit_product_overdraft_policies"

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
    end
  end
end
