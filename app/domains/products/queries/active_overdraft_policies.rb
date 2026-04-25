# frozen_string_literal: true

module Products
  module Queries
    class ActiveOverdraftPolicies
      def self.deny_nsf(business_date:, deposit_product_id: nil)
        scope = Models::DepositProductOverdraftPolicy
          .includes(:deposit_product)
          .where(
            mode: Models::DepositProductOverdraftPolicy::MODE_DENY_NSF
          )
        scope = Services::EffectiveDatedResolver.active_scope(scope, as_of: business_date)
          .order(:deposit_product_id, :effective_on, :id)
        scope = scope.where(deposit_product_id: deposit_product_id) if deposit_product_id.present?
        scope
      end

      def self.deny_nsf_for_product(business_date:, deposit_product_id:)
        scope = Models::DepositProductOverdraftPolicy.where(
          deposit_product_id: deposit_product_id,
          mode: Models::DepositProductOverdraftPolicy::MODE_DENY_NSF
        )
        Services::EffectiveDatedResolver.resolve_one(scope, as_of: business_date)
      end
    end
  end
end
