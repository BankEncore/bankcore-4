# frozen_string_literal: true

require "test_helper"

class ProductsActiveStatementProfilesTest < ActiveSupport::TestCase
  setup do
    @product = create_product!("statement-active")
    @other_product = create_product!("statement-other")
  end

  test "returns active monthly profiles effective on business date" do
    active = create_profile!(@product, effective_on: Date.new(2026, 4, 1))
    create_profile!(@product, effective_on: Date.new(2026, 5, 1))
    create_profile!(@product, status: Products::Models::DepositProductStatementProfile::STATUS_INACTIVE)
    create_profile!(@product, effective_on: Date.new(2026, 3, 1), ended_on: Date.new(2026, 3, 31))

    profiles = Products::Queries::ActiveStatementProfiles.monthly(business_date: Date.new(2026, 4, 15)).to_a

    assert_includes profiles, active
    assert_equal 1, profiles.count { |p| p.deposit_product_id == @product.id }
  end

  test "product filter limits profiles" do
    create_profile!(@product)
    other = create_profile!(@other_product)

    profiles = Products::Queries::ActiveStatementProfiles.monthly(
      business_date: Date.new(2026, 4, 15),
      deposit_product_id: @other_product.id
    ).to_a

    assert_equal [ other ], profiles
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

  def create_profile!(product, attrs = {})
    Products::Models::DepositProductStatementProfile.create!({
      deposit_product: product,
      frequency: Products::Models::DepositProductStatementProfile::FREQUENCY_MONTHLY,
      cycle_day: 1,
      currency: "USD",
      status: Products::Models::DepositProductStatementProfile::STATUS_ACTIVE,
      effective_on: Date.new(2026, 4, 1)
    }.merge(attrs))
  end
end
