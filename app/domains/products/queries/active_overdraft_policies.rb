# frozen_string_literal: true

module Products
  module Queries
    class ActiveOverdraftPolicies
      def self.deny_nsf(business_date:, deposit_product_id: nil)
        scope = Models::DepositProductOverdraftPolicy
          .includes(:deposit_product)
          .where(
            mode: Models::DepositProductOverdraftPolicy::MODE_DENY_NSF,
            status: Models::DepositProductOverdraftPolicy::STATUS_ACTIVE
          )
          .where("effective_on <= ?", business_date)
          .where("ended_on IS NULL OR ended_on >= ?", business_date)
          .order(:deposit_product_id, :effective_on, :id)
        scope = scope.where(deposit_product_id: deposit_product_id) if deposit_product_id.present?
        scope
      end

      def self.deny_nsf_for_product(business_date:, deposit_product_id:)
        deny_nsf(business_date: business_date, deposit_product_id: deposit_product_id).last
      end
    end
  end
end
