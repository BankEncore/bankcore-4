# frozen_string_literal: true

module Products
  module Queries
    class ActiveFeeRules
      def self.monthly_maintenance(business_date:, deposit_product_id: nil)
        scope = Models::DepositProductFeeRule
          .includes(:deposit_product)
          .where(
            fee_code: Models::DepositProductFeeRule::FEE_CODE_MONTHLY_MAINTENANCE
          )
        scope = Services::EffectiveDatedResolver.active_scope(scope, as_of: business_date)
          .order(:deposit_product_id, :effective_on, :id)
        scope = scope.where(deposit_product_id: deposit_product_id) if deposit_product_id.present?
        scope
      end

      def self.monthly_maintenance_for_product(business_date:, deposit_product_id:)
        scope = Models::DepositProductFeeRule.where(
          deposit_product_id: deposit_product_id,
          fee_code: Models::DepositProductFeeRule::FEE_CODE_MONTHLY_MAINTENANCE
        )
        Services::EffectiveDatedResolver.resolve_one(scope, as_of: business_date)
      end
    end
  end
end
