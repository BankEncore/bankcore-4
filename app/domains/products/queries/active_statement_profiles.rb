# frozen_string_literal: true

module Products
  module Queries
    class ActiveStatementProfiles
      def self.monthly(business_date:, deposit_product_id: nil)
        scope = Models::DepositProductStatementProfile
          .includes(:deposit_product)
          .where(
            frequency: Models::DepositProductStatementProfile::FREQUENCY_MONTHLY,
            status: Models::DepositProductStatementProfile::STATUS_ACTIVE
          )
          .where("effective_on <= ?", business_date)
          .where("ended_on IS NULL OR ended_on >= ?", business_date)
          .order(:deposit_product_id, :effective_on, :id)
        scope = scope.where(deposit_product_id: deposit_product_id) if deposit_product_id.present?
        scope
      end
    end
  end
end
