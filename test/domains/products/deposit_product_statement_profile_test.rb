# frozen_string_literal: true

require "test_helper"

class ProductsDepositProductStatementProfileTest < ActiveSupport::TestCase
  setup do
    @product = Products::Models::DepositProduct.create!(
      product_code: "statement_profile_#{SecureRandom.hex(4)}",
      name: "Statement Profile Product",
      status: Products::Models::DepositProduct::STATUS_ACTIVE,
      currency: "USD"
    )
  end

  test "valid monthly profile" do
    profile = build_profile
    assert_predicate profile, :valid?
  end

  test "rejects unsupported frequency" do
    profile = build_profile(frequency: "quarterly")
    assert_not profile.valid?
    assert_includes profile.errors[:frequency], "is not included in the list"
  end

  test "rejects cycle day outside supported range" do
    profile = build_profile(cycle_day: 32)
    assert_not profile.valid?
    assert_includes profile.errors[:cycle_day], "must be less than or equal to 31"
  end

  test "rejects ended_on before effective_on" do
    profile = build_profile(effective_on: Date.new(2026, 4, 2), ended_on: Date.new(2026, 4, 1))
    assert_not profile.valid?
    assert_includes profile.errors[:ended_on], "must be on or after effective_on"
  end

  test "rejects currency mismatch" do
    profile = build_profile(currency: "EUR")
    assert_not profile.valid?
    assert_includes profile.errors[:currency], "must match deposit product currency"
  end

  private

  def build_profile(attrs = {})
    Products::Models::DepositProductStatementProfile.new({
      deposit_product: @product,
      frequency: Products::Models::DepositProductStatementProfile::FREQUENCY_MONTHLY,
      cycle_day: 1,
      currency: "USD",
      status: Products::Models::DepositProductStatementProfile::STATUS_ACTIVE,
      effective_on: Date.new(2026, 4, 1)
    }.merge(attrs))
  end
end
