# frozen_string_literal: true

module Admin
  class DepositProductsController < ApplicationController
    def index
      @deposit_products = Products::Models::DepositProduct
        .left_joins(:deposit_product_fee_rules, :deposit_product_overdraft_policies, :deposit_product_statement_profiles)
        .select(
          "deposit_products.*",
          "COUNT(DISTINCT deposit_product_fee_rules.id) AS fee_rules_count",
          "COUNT(DISTINCT deposit_product_overdraft_policies.id) AS overdraft_policies_count",
          "COUNT(DISTINCT deposit_product_statement_profiles.id) AS statement_profiles_count"
        )
        .group("deposit_products.id")
        .order(:product_code)
    end

    def show
      @deposit_product = Products::Models::DepositProduct.includes(
        :deposit_product_fee_rules,
        :deposit_product_overdraft_policies,
        :deposit_product_statement_profiles
      ).find(params[:id])
    end
  end
end
