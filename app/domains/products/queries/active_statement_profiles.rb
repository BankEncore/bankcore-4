# frozen_string_literal: true

module Products
  module Queries
    class ActiveStatementProfiles
      def self.monthly(business_date:, deposit_product_id: nil)
        scope = Models::DepositProductStatementProfile
          .includes(:deposit_product)
          .where(
            frequency: Models::DepositProductStatementProfile::FREQUENCY_MONTHLY
          )
        scope = Services::EffectiveDatedResolver.active_scope(scope, as_of: business_date)
          .order(:deposit_product_id, :effective_on, :id)
        scope = scope.where(deposit_product_id: deposit_product_id) if deposit_product_id.present?
        scope
      end

      def self.monthly_for_product(business_date:, deposit_product_id:)
        scope = Models::DepositProductStatementProfile.where(
          deposit_product_id: deposit_product_id,
          frequency: Models::DepositProductStatementProfile::FREQUENCY_MONTHLY
        )
        Services::EffectiveDatedResolver.resolve_one(scope, as_of: business_date)
      end
    end
  end
end
