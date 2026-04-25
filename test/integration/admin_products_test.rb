# frozen_string_literal: true

require "test_helper"

class AdminProductsTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_operator_with_credential!(role: "admin", username: "admin-products")
    @product = create_product!(code: "adm_product_#{SecureRandom.hex(4)}", name: "Admin Product")
    @other_product = create_product!(code: "adm_other_#{SecureRandom.hex(4)}", name: "Other Product")
    create_config_rows!(@product)
  end

  test "admin pages are available to admin but forbidden to non-admin internal users" do
    internal_login!(username: "admin-products")
    get "/admin/deposit_products"
    assert_response :success
    delete "/logout"

    create_operator_with_credential!(role: "operations", username: "non-admin-ops")
    internal_login!(username: "non-admin-ops")
    get "/admin/deposit_products"
    assert_response :forbidden
    delete "/logout"

    create_operator_with_credential!(role: "supervisor", username: "non-admin-supervisor")
    internal_login!(username: "non-admin-supervisor")
    get "/admin/deposit_product_fee_rules"
    assert_response :forbidden
  end

  test "product list and detail show related configuration and empty states" do
    internal_login!(username: "admin-products")

    get "/admin/deposit_products"
    assert_response :success
    assert_includes response.body, @product.product_code
    assert_includes response.body, @other_product.product_code
    assert_includes response.body, ">1<"

    get "/admin/deposit_products/#{@product.id}"
    assert_response :success
    assert_includes response.body, "monthly_maintenance"
    assert_includes response.body, "deny_nsf"
    assert_includes response.body, "monthly"
    assert_includes response.body, admin_deposit_product_fee_rules_path(deposit_product_id: @product.id)

    empty_product = create_product!(code: "adm_empty_#{SecureRandom.hex(4)}", name: "Empty Product")
    get "/admin/deposit_products/#{empty_product.id}"
    assert_response :success
    assert_includes response.body, "No fee rules configured for this product."
    assert_includes response.body, "No overdraft policies configured for this product."
    assert_includes response.body, "No statement profiles configured for this product."
  end

  test "fee rule index supports raw rows product filter active-as-of and invalid date" do
    inactive_fee = Products::Models::DepositProductFeeRule.create!(
      deposit_product: @product,
      fee_code: Products::Models::DepositProductFeeRule::FEE_CODE_MONTHLY_MAINTENANCE,
      amount_minor_units: 700,
      currency: "USD",
      status: Products::Models::DepositProductFeeRule::STATUS_INACTIVE,
      effective_on: Date.new(2026, 4, 1),
      description: "Inactive fee"
    )
    other_fee = Products::Models::DepositProductFeeRule.create!(
      deposit_product: @other_product,
      fee_code: Products::Models::DepositProductFeeRule::FEE_CODE_MONTHLY_MAINTENANCE,
      amount_minor_units: 900,
      currency: "USD",
      status: Products::Models::DepositProductFeeRule::STATUS_ACTIVE,
      effective_on: Date.new(2026, 4, 1),
      description: "Other fee"
    )

    internal_login!(username: "admin-products")
    get "/admin/deposit_product_fee_rules", params: { deposit_product_id: @product.id }
    assert_response :success
    assert_includes response.body, "Monthly maintenance fee"
    assert_includes response.body, inactive_fee.description
    assert_no_match(/#{Regexp.escape(other_fee.description)}/, response.body)

    get "/admin/deposit_product_fee_rules", params: { deposit_product_id: @product.id, as_of: "2026-05-01" }
    assert_response :success
    assert_includes response.body, "Showing active configuration as of 2026-05-01"
    assert_includes response.body, "Monthly maintenance fee"
    assert_no_match(/#{Regexp.escape(inactive_fee.description)}/, response.body)

    get "/admin/deposit_product_fee_rules", params: { as_of: "not-a-date" }
    assert_response :success
    assert_includes response.body, "as_of must be a valid ISO 8601 date"
  end

  test "overdraft and statement indexes support active-as-of filtering" do
    future_policy = Products::Models::DepositProductOverdraftPolicy.create!(
      deposit_product: @product,
      mode: Products::Models::DepositProductOverdraftPolicy::MODE_DENY_NSF,
      nsf_fee_minor_units: 4_500,
      currency: "USD",
      status: Products::Models::DepositProductOverdraftPolicy::STATUS_ACTIVE,
      effective_on: Date.new(2027, 1, 1),
      description: "Future NSF policy"
    )
    future_profile = Products::Models::DepositProductStatementProfile.create!(
      deposit_product: @product,
      frequency: Products::Models::DepositProductStatementProfile::FREQUENCY_MONTHLY,
      cycle_day: 15,
      currency: "USD",
      status: Products::Models::DepositProductStatementProfile::STATUS_ACTIVE,
      effective_on: Date.new(2027, 1, 1),
      description: "Future statement profile"
    )

    internal_login!(username: "admin-products")

    get "/admin/deposit_product_overdraft_policies", params: { deposit_product_id: @product.id }
    assert_response :success
    assert_includes response.body, future_policy.description

    get "/admin/deposit_product_overdraft_policies", params: { deposit_product_id: @product.id, as_of: "2026-05-01" }
    assert_response :success
    assert_includes response.body, "Seeded deny-NSF policy"
    assert_no_match(/#{Regexp.escape(future_policy.description)}/, response.body)

    get "/admin/deposit_product_statement_profiles", params: { deposit_product_id: @product.id }
    assert_response :success
    assert_includes response.body, future_profile.description

    get "/admin/deposit_product_statement_profiles", params: { deposit_product_id: @product.id, as_of: "2026-05-01" }
    assert_response :success
    assert_includes response.body, "Seeded monthly statement profile"
    assert_no_match(/#{Regexp.escape(future_profile.description)}/, response.body)
  end

  private

  def create_product!(code:, name:)
    Products::Models::DepositProduct.create!(
      product_code: code,
      name: name,
      status: Products::Models::DepositProduct::STATUS_ACTIVE,
      currency: "USD"
    )
  end

  def create_config_rows!(product)
    Products::Models::DepositProductFeeRule.create!(
      deposit_product: product,
      fee_code: Products::Models::DepositProductFeeRule::FEE_CODE_MONTHLY_MAINTENANCE,
      amount_minor_units: 500,
      currency: "USD",
      status: Products::Models::DepositProductFeeRule::STATUS_ACTIVE,
      effective_on: Date.new(2026, 4, 1),
      description: "Monthly maintenance fee"
    )
    Products::Models::DepositProductOverdraftPolicy.create!(
      deposit_product: product,
      mode: Products::Models::DepositProductOverdraftPolicy::MODE_DENY_NSF,
      nsf_fee_minor_units: 3_500,
      currency: "USD",
      status: Products::Models::DepositProductOverdraftPolicy::STATUS_ACTIVE,
      effective_on: Date.new(2026, 4, 1),
      ended_on: Date.new(2026, 12, 31),
      description: "Seeded deny-NSF policy"
    )
    Products::Models::DepositProductStatementProfile.create!(
      deposit_product: product,
      frequency: Products::Models::DepositProductStatementProfile::FREQUENCY_MONTHLY,
      cycle_day: 1,
      currency: "USD",
      status: Products::Models::DepositProductStatementProfile::STATUS_ACTIVE,
      effective_on: Date.new(2026, 4, 1),
      ended_on: Date.new(2026, 12, 31),
      description: "Seeded monthly statement profile"
    )
  end
end
