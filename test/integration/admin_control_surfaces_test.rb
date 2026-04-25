# frozen_string_literal: true

require "test_helper"

class AdminControlSurfacesTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_operator_with_credential!(role: "admin", username: "admin-controls")
    @product = Products::Models::DepositProduct.create!(
      product_code: "admin_ctrl_#{SecureRandom.hex(4)}",
      name: "Admin Control Product",
      status: Products::Models::DepositProduct::STATUS_ACTIVE,
      currency: "USD"
    )
  end

  test "admin can preview and create fee rule without side effects during preview" do
    internal_login!(username: "admin-controls")

    get "/admin/rule_changes/fee_rule/new", params: { deposit_product_id: @product.id }
    assert_response :success
    assert_includes response.body, "New fee rule"

    assert_no_difference -> { Products::Models::DepositProductFeeRule.count } do
      post "/admin/rule_changes/fee_rule/preview",
        params: {
          rule_change: {
            deposit_product_id: @product.id,
            amount_minor_units: 600,
            currency: "USD",
            effective_on: "2026-09-01",
            description: "Previewed fee"
          }
        }
      assert_response :success
      assert_includes response.body, "Change summary"
    end

    assert_difference -> { Products::Models::DepositProductFeeRule.count }, 1 do
      post "/admin/rule_changes/fee_rule",
        params: {
          rule_change: {
            deposit_product_id: @product.id,
            amount_minor_units: 600,
            currency: "USD",
            effective_on: "2026-09-01",
            description: "Previewed fee"
          }
        }
    end
    assert_redirected_to "/admin/deposit_product_fee_rules"
    assert_equal "Previewed fee", Products::Models::DepositProductFeeRule.order(:id).last.description
  end

  test "admin create supersedes existing overdraft policy after confirmation" do
    existing = Products::Models::DepositProductOverdraftPolicy.create!(
      deposit_product: @product,
      mode: Products::Models::DepositProductOverdraftPolicy::MODE_DENY_NSF,
      nsf_fee_minor_units: 3_500,
      currency: "USD",
      status: Products::Models::DepositProductOverdraftPolicy::STATUS_ACTIVE,
      effective_on: Date.new(2026, 1, 1)
    )

    internal_login!(username: "admin-controls")
    post "/admin/rule_changes/overdraft_policy/preview",
      params: {
        rule_change: {
          deposit_product_id: @product.id,
          nsf_fee_minor_units: 4_500,
          currency: "USD",
          effective_on: "2026-10-01"
        }
      }
    assert_response :success
    assert_includes response.body, "Rows that will be superseded"

    post "/admin/rule_changes/overdraft_policy",
      params: {
        rule_change: {
          deposit_product_id: @product.id,
          nsf_fee_minor_units: 4_500,
          currency: "USD",
          effective_on: "2026-10-01"
        }
      }
    assert_redirected_to "/admin/deposit_product_overdraft_policies"
    assert_equal Date.new(2026, 9, 30), existing.reload.ended_on
  end

  test "admin can preview and confirm statement profile end date without deleting it" do
    profile = Products::Models::DepositProductStatementProfile.create!(
      deposit_product: @product,
      frequency: Products::Models::DepositProductStatementProfile::FREQUENCY_MONTHLY,
      cycle_day: 15,
      currency: "USD",
      status: Products::Models::DepositProductStatementProfile::STATUS_ACTIVE,
      effective_on: Date.new(2026, 1, 1)
    )

    internal_login!(username: "admin-controls")
    post "/admin/rule_changes/statement_profile/#{profile.id}/end_date_preview",
      params: { rule_change: { ended_on: "2026-12-31" } }
    assert_response :success
    assert_includes response.body, "End-date statement profile"

    assert_no_difference -> { Products::Models::DepositProductStatementProfile.count } do
      patch "/admin/rule_changes/statement_profile/#{profile.id}/end_date",
        params: { rule_change: { ended_on: "2026-12-31" } }
    end
    assert_redirected_to "/admin/deposit_product_statement_profiles"
    assert_equal Date.new(2026, 12, 31), profile.reload.ended_on
  end

  test "admin control errors render validation and non-admin remains forbidden" do
    internal_login!(username: "admin-controls")
    post "/admin/rule_changes/fee_rule/preview",
      params: {
        rule_change: {
          deposit_product_id: @product.id,
          amount_minor_units: 600,
          currency: "EUR",
          effective_on: "2026-09-01"
        }
      }
    assert_response :unprocessable_entity
    assert_includes response.body, "must match deposit product currency"
    delete "/logout"

    create_operator_with_credential!(role: "operations", username: "admin-control-ops")
    internal_login!(username: "admin-control-ops")
    get "/admin/rule_changes/fee_rule/new"
    assert_response :forbidden
  end
end
