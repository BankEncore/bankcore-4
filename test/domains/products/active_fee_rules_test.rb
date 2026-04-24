# frozen_string_literal: true

require "test_helper"

class ProductsActiveFeeRulesTest < ActiveSupport::TestCase
  setup do
    @product = create_product!("active-fee-rules")
    @other_product = create_product!("other-fee-rules")
  end

  test "returns active monthly maintenance rules effective on date" do
    active = create_rule!(@product, effective_on: Date.new(2026, 4, 1))
    create_rule!(@product, status: Products::Models::DepositProductFeeRule::STATUS_INACTIVE)
    create_rule!(@product, effective_on: Date.new(2026, 5, 1))
    create_rule!(@product, effective_on: Date.new(2026, 3, 1), ended_on: Date.new(2026, 4, 20))

    rules = Products::Queries::ActiveFeeRules.monthly_maintenance(
      business_date: Date.new(2026, 4, 22),
      deposit_product_id: @product.id
    )

    assert_equal [ active.id ], rules.map(&:id)
  end

  test "filters by deposit product" do
    selected = create_rule!(@product)
    create_rule!(@other_product)

    rules = Products::Queries::ActiveFeeRules.monthly_maintenance(
      business_date: Date.new(2026, 4, 22),
      deposit_product_id: @product.id
    )

    assert_equal [ selected.id ], rules.map(&:id)
  end

  private

  def create_product!(prefix)
    Products::Models::DepositProduct.create!(
      product_code: "#{prefix}-#{SecureRandom.hex(4)}",
      name: prefix,
      status: Products::Models::DepositProduct::STATUS_ACTIVE,
      currency: "USD"
    )
  end

  def create_rule!(product, attrs = {})
    Products::Models::DepositProductFeeRule.create!({
      deposit_product: product,
      fee_code: Products::Models::DepositProductFeeRule::FEE_CODE_MONTHLY_MAINTENANCE,
      amount_minor_units: 500,
      currency: "USD",
      status: Products::Models::DepositProductFeeRule::STATUS_ACTIVE,
      effective_on: Date.new(2026, 4, 1)
    }.merge(attrs))
  end
end
