# frozen_string_literal: true

require "test_helper"

class ProductsDepositProductOverdraftPolicyTest < ActiveSupport::TestCase
  setup do
    @product = Products::Models::DepositProduct.create!(
      product_code: "od_policy_#{SecureRandom.hex(4)}",
      name: "OD Policy Product",
      status: Products::Models::DepositProduct::STATUS_ACTIVE,
      currency: "USD"
    )
  end

  test "valid deny NSF policy" do
    policy = build_policy
    assert_predicate policy, :valid?
  end

  test "rejects non-positive NSF fee" do
    policy = build_policy(nsf_fee_minor_units: 0)
    assert_not policy.valid?
    assert_includes policy.errors[:nsf_fee_minor_units], "must be greater than 0"
  end

  test "rejects unsupported mode" do
    policy = build_policy(mode: "allow_overdraft")
    assert_not policy.valid?
    assert_includes policy.errors[:mode], "is not included in the list"
  end

  test "rejects ended_on before effective_on" do
    policy = build_policy(effective_on: Date.new(2026, 4, 2), ended_on: Date.new(2026, 4, 1))
    assert_not policy.valid?
    assert_includes policy.errors[:ended_on], "must be on or after effective_on"
  end

  test "rejects currency mismatch" do
    policy = build_policy(currency: "EUR")
    assert_not policy.valid?
    assert_includes policy.errors[:currency], "must match deposit product currency"
  end

  test "rejects overlapping active deny NSF policy" do
    build_policy(effective_on: Date.new(2026, 4, 1), ended_on: Date.new(2026, 4, 30)).save!
    policy = build_policy(effective_on: Date.new(2026, 4, 15))

    assert_not policy.valid?
    assert_includes policy.errors[:effective_on], "overlaps an active deny NSF policy for this product"
  end

  test "allows adjacent active deny NSF policy" do
    build_policy(effective_on: Date.new(2026, 4, 1), ended_on: Date.new(2026, 4, 30)).save!
    policy = build_policy(effective_on: Date.new(2026, 5, 1))

    assert_predicate policy, :valid?
  end

  private

  def build_policy(attrs = {})
    Products::Models::DepositProductOverdraftPolicy.new({
      deposit_product: @product,
      mode: Products::Models::DepositProductOverdraftPolicy::MODE_DENY_NSF,
      nsf_fee_minor_units: 3_500,
      currency: "USD",
      status: Products::Models::DepositProductOverdraftPolicy::STATUS_ACTIVE,
      effective_on: Date.new(2026, 4, 1)
    }.merge(attrs))
  end
end
