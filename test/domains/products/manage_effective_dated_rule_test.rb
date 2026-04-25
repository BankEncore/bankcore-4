# frozen_string_literal: true

require "test_helper"

module Products
  module Commands
    class ManageEffectiveDatedRuleTest < ActiveSupport::TestCase
      setup do
        @product = Models::DepositProduct.create!(
          product_code: "cmd_rule_#{SecureRandom.hex(4)}",
          name: "Command Rule Product",
          status: Models::DepositProduct::STATUS_ACTIVE,
          currency: "USD"
        )
      end

      test "preview create has no side effects and reports superseded active rows" do
        existing = Models::DepositProductFeeRule.create!(
          deposit_product: @product,
          fee_code: Models::DepositProductFeeRule::FEE_CODE_MONTHLY_MAINTENANCE,
          amount_minor_units: 500,
          currency: "USD",
          status: Models::DepositProductFeeRule::STATUS_ACTIVE,
          effective_on: Date.new(2026, 1, 1)
        )

        assert_no_difference -> { Models::DepositProductFeeRule.count } do
          result = ManageEffectiveDatedRule.preview_create(
            rule_kind: "fee_rule",
            attributes: {
              deposit_product_id: @product.id,
              amount_minor_units: 700,
              effective_on: "2026-06-01",
              currency: "USD"
            }
          )

          assert result.preview
          assert_equal [ existing ], result.superseded_rules
          assert_equal 700, result.rule.amount_minor_units
        end
      end

      test "create supersedes existing active row and persists new rule" do
        existing = Models::DepositProductOverdraftPolicy.create!(
          deposit_product: @product,
          mode: Models::DepositProductOverdraftPolicy::MODE_DENY_NSF,
          nsf_fee_minor_units: 3_500,
          currency: "USD",
          status: Models::DepositProductOverdraftPolicy::STATUS_ACTIVE,
          effective_on: Date.new(2026, 1, 1)
        )

        result = ManageEffectiveDatedRule.create(
          rule_kind: "overdraft_policy",
          attributes: {
            deposit_product_id: @product.id,
            nsf_fee_minor_units: 4_000,
            effective_on: "2026-07-01",
            currency: "USD",
            description: "Updated NSF fee"
          }
        )

        assert_not result.preview
        assert_equal Date.new(2026, 6, 30), existing.reload.ended_on
        assert_equal 4_000, result.rule.nsf_fee_minor_units
        assert_equal "Updated NSF fee", result.rule.description
      end

      test "end date validates effective range without deleting row" do
        profile = Models::DepositProductStatementProfile.create!(
          deposit_product: @product,
          frequency: Models::DepositProductStatementProfile::FREQUENCY_MONTHLY,
          cycle_day: 5,
          currency: "USD",
          status: Models::DepositProductStatementProfile::STATUS_ACTIVE,
          effective_on: Date.new(2026, 1, 1)
        )

        result = ManageEffectiveDatedRule.end_date(
          rule_kind: "statement_profile",
          rule_id: profile.id,
          ended_on: "2026-12-31"
        )

        assert_equal profile.id, result.rule.id
        assert_equal Date.new(2026, 12, 31), profile.reload.ended_on
      end

      test "create rejects overlapping future row instead of silently rewriting it" do
        Models::DepositProductFeeRule.create!(
          deposit_product: @product,
          fee_code: Models::DepositProductFeeRule::FEE_CODE_MONTHLY_MAINTENANCE,
          amount_minor_units: 500,
          currency: "USD",
          status: Models::DepositProductFeeRule::STATUS_ACTIVE,
          effective_on: Date.new(2026, 8, 1)
        )

        error = assert_raises(ManageEffectiveDatedRule::InvalidRequest) do
          ManageEffectiveDatedRule.create(
            rule_kind: "fee_rule",
            attributes: {
              deposit_product_id: @product.id,
              amount_minor_units: 700,
              effective_on: "2026-06-01",
              currency: "USD"
            }
          )
        end

        assert_match(/overlapping active rows/, error.message)
      end
    end
  end
end
