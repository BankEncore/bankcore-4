# frozen_string_literal: true

module Products
  module Services
    class DepositProductResolver
      DepositBehavior = Data.define(
        :deposit_product,
        :monthly_maintenance_fee_rule,
        :deny_nsf_policy,
        :monthly_statement_profile
      )

      def self.call(as_of:, deposit_account: nil, deposit_product_id: nil)
        product = resolve_product!(deposit_account: deposit_account, deposit_product_id: deposit_product_id)
        product_id = product.id

        DepositBehavior.new(
          deposit_product: product,
          monthly_maintenance_fee_rule: Queries::ActiveFeeRules.monthly_maintenance_for_product(
            business_date: as_of,
            deposit_product_id: product_id
          ),
          deny_nsf_policy: Queries::ActiveOverdraftPolicies.deny_nsf_for_product(
            business_date: as_of,
            deposit_product_id: product_id
          ),
          monthly_statement_profile: Queries::ActiveStatementProfiles.monthly_for_product(
            business_date: as_of,
            deposit_product_id: product_id
          )
        )
      end

      def self.resolve_product!(deposit_account:, deposit_product_id:)
        if deposit_account
          return deposit_account.deposit_product if deposit_account.respond_to?(:deposit_product)

          return Models::DepositProduct.find(deposit_account.deposit_product_id)
        end

        raise ArgumentError, "deposit_account or deposit_product_id is required" if deposit_product_id.blank?

        Models::DepositProduct.find(deposit_product_id)
      end
      private_class_method :resolve_product!
    end
  end
end
