# frozen_string_literal: true

require "test_helper"

class ProductsActiveOverdraftPoliciesTest < ActiveSupport::TestCase
  setup do
    @product = create_product!("active-od-policies")
    @other_product = create_product!("other-od-policies")
  end

  test "returns active deny NSF policies effective on date" do
    active = create_policy!(@product, effective_on: Date.new(2026, 4, 1))
    create_policy!(@product, status: Products::Models::DepositProductOverdraftPolicy::STATUS_INACTIVE)
    create_policy!(@product, effective_on: Date.new(2026, 5, 1))
    create_policy!(@product, effective_on: Date.new(2026, 3, 1), ended_on: Date.new(2026, 4, 20))

    policies = Products::Queries::ActiveOverdraftPolicies.deny_nsf(
      business_date: Date.new(2026, 4, 22),
      deposit_product_id: @product.id
    )

    assert_equal [ active.id ], policies.map(&:id)
  end

  test "filters by deposit product" do
    selected = create_policy!(@product)
    create_policy!(@other_product)

    policies = Products::Queries::ActiveOverdraftPolicies.deny_nsf(
      business_date: Date.new(2026, 4, 22),
      deposit_product_id: @product.id
    )

    assert_equal [ selected.id ], policies.map(&:id)
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

  def create_policy!(product, attrs = {})
    Products::Models::DepositProductOverdraftPolicy.create!({
      deposit_product: product,
      mode: Products::Models::DepositProductOverdraftPolicy::MODE_DENY_NSF,
      nsf_fee_minor_units: 3_500,
      currency: "USD",
      status: Products::Models::DepositProductOverdraftPolicy::STATUS_ACTIVE,
      effective_on: Date.new(2026, 4, 1)
    }.merge(attrs))
  end
end
