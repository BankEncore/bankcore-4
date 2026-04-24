# frozen_string_literal: true

require "test_helper"

class ProductsDepositProductFeeRuleTest < ActiveSupport::TestCase
  setup do
    @product = Products::Models::DepositProduct.create!(
      product_code: "fee_rule_#{SecureRandom.hex(4)}",
      name: "Fee Rule Product",
      status: Products::Models::DepositProduct::STATUS_ACTIVE,
      currency: "USD"
    )
  end

  test "valid monthly maintenance rule" do
    rule = Products::Models::DepositProductFeeRule.new(
      deposit_product: @product,
      fee_code: Products::Models::DepositProductFeeRule::FEE_CODE_MONTHLY_MAINTENANCE,
      amount_minor_units: 500,
      currency: "USD",
      status: Products::Models::DepositProductFeeRule::STATUS_ACTIVE,
      effective_on: Date.new(2026, 4, 1)
    )

    assert_predicate rule, :valid?
  end

  test "rejects non-positive amount" do
    rule = build_rule(amount_minor_units: 0)
    assert_not rule.valid?
    assert_includes rule.errors[:amount_minor_units], "must be greater than 0"
  end

  test "rejects unsupported fee code" do
    rule = build_rule(fee_code: "statement_copy")
    assert_not rule.valid?
    assert_includes rule.errors[:fee_code], "is not included in the list"
  end

  test "rejects ended_on before effective_on" do
    rule = build_rule(effective_on: Date.new(2026, 4, 2), ended_on: Date.new(2026, 4, 1))
    assert_not rule.valid?
    assert_includes rule.errors[:ended_on], "must be on or after effective_on"
  end

  test "rejects currency mismatch with product" do
    rule = build_rule(currency: "EUR")
    assert_not rule.valid?
    assert_includes rule.errors[:currency], "must match deposit product currency"
  end

  private

  def build_rule(attrs = {})
    Products::Models::DepositProductFeeRule.new({
      deposit_product: @product,
      fee_code: Products::Models::DepositProductFeeRule::FEE_CODE_MONTHLY_MAINTENANCE,
      amount_minor_units: 500,
      currency: "USD",
      status: Products::Models::DepositProductFeeRule::STATUS_ACTIVE,
      effective_on: Date.new(2026, 4, 1)
    }.merge(attrs))
  end
end
