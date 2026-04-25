# frozen_string_literal: true

require "test_helper"

class InternalWorkspacePhase35bTest < ActionDispatch::IntegrationTest
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 22))

    @teller = create_operator_with_credential!(role: "teller", username: "branch-teller")
    @operations = create_operator_with_credential!(role: "operations", username: "ops-user")
    @admin = create_operator_with_credential!(role: "admin", username: "admin-user")
  end

  test "branch workspace exposes session and transaction parity routes" do
    internal_login!(username: "branch-teller")

    get branch_path
    assert_response :success
    assert_includes response.body, "Open session"
    assert_includes response.body, "Transfer"
    assert_includes response.body, "Place hold"

    get new_branch_teller_session_path
    assert_response :success
    assert_includes response.body, "Open teller session"

    get new_branch_transfer_path
    assert_response :success
    assert_includes response.body, "Record transfer"

    get new_branch_hold_path
    assert_response :success
    assert_includes response.body, "Place hold"

    get branch_operational_events_path
    assert_response :success
    assert_includes response.body, "Branch operational events"
  end

  test "ops workspace exposes close package and exception queues" do
    internal_login!(username: "ops-user")

    get ops_path
    assert_response :success
    assert_includes response.body, "Close package"
    assert_includes response.body, "Exception queues"

    get ops_close_package_path
    assert_response :success
    assert_includes response.body, "Close package"

    get ops_exceptions_path
    assert_response :success
    assert_includes response.body, "Exception queues"
  end

  test "admin product workspace exposes readiness review" do
    internal_login!(username: "admin-user")
    product = Products::Queries::FindDepositProduct.default_slice1!

    get admin_deposit_product_path(product)
    assert_response :success
    assert_includes response.body, "Readiness"

    get admin_deposit_product_readiness_path(product)
    assert_response :success
    assert_includes response.body, "Product readiness"
  end
end
