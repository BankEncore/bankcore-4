# frozen_string_literal: true

module BankCore
  module Seeds
    module DepositProducts
      # Idempotent seed for development and test (migration also inserts slice-1 row for existing DBs).
      def self.seed!
        Products::Models::DepositProduct.find_or_create_by!(product_code: Accounts::SLICE1_PRODUCT_CODE) do |p|
          p.name = "Slice 1 demand deposit (seeded)"
          p.status = Products::Models::DepositProduct::STATUS_ACTIVE
          p.currency = "USD"
        end.tap do |product|
          Products::Models::DepositProductFeeRule.find_or_create_by!(
            deposit_product: product,
            fee_code: Products::Models::DepositProductFeeRule::FEE_CODE_MONTHLY_MAINTENANCE,
            effective_on: Date.new(2026, 4, 1)
          ) do |rule|
            rule.amount_minor_units = 500
            rule.currency = product.currency
            rule.status = Products::Models::DepositProductFeeRule::STATUS_ACTIVE
            rule.description = "Seeded monthly maintenance fee for P3-3"
          end
          Products::Models::DepositProductOverdraftPolicy.find_or_create_by!(
            deposit_product: product,
            mode: Products::Models::DepositProductOverdraftPolicy::MODE_DENY_NSF,
            effective_on: Date.new(2026, 4, 1)
          ) do |policy|
            policy.nsf_fee_minor_units = 3_500
            policy.currency = product.currency
            policy.status = Products::Models::DepositProductOverdraftPolicy::STATUS_ACTIVE
            policy.description = "Seeded deny-NSF policy for P3-4"
          end
        end
      end
    end
  end
end
