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
        :deposit_product_statement_profiles,
        :deposit_accounts
      ).find(params[:id])
      @account_counts = @deposit_product.deposit_accounts.group(:status).count
      @recent_accounts = @deposit_product.deposit_accounts.order(created_at: :desc, id: :desc).limit(10)
    end

    def readiness
      @deposit_product = Products::Models::DepositProduct.includes(
        :deposit_product_fee_rules,
        :deposit_product_overdraft_policies,
        :deposit_product_statement_profiles
      ).find(params[:id])
      @as_of = parse_optional_date_param(:as_of) || Core::BusinessDate::Services::CurrentBusinessDate.call
      return if @error_message.present?

      @checks = product_readiness_checks(@deposit_product, @as_of)
    rescue Core::BusinessDate::Errors::NotSet => e
      @error_message = e.message
    end

    private

    def product_readiness_checks(product, as_of)
      [
        readiness_check("Product active", product.status == Products::Models::DepositProduct::STATUS_ACTIVE),
        readiness_check("Active monthly maintenance fee rule",
          Products::Queries::ActiveFeeRules.monthly_maintenance(business_date: as_of, deposit_product_id: product.id).exists?),
        readiness_check("Active deny-NSF overdraft policy",
          Products::Queries::ActiveOverdraftPolicies.deny_nsf_for_product(business_date: as_of, deposit_product_id: product.id).present?),
        readiness_check("Active monthly statement profile",
          Products::Queries::ActiveStatementProfiles.monthly(business_date: as_of, deposit_product_id: product.id).exists?)
      ]
    end

    def readiness_check(label, ready)
      { label: label, ready: ready }
    end
  end
end
