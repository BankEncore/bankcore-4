# frozen_string_literal: true

require "test_helper"

class BranchCashSurfacesTest < ActionDispatch::IntegrationTest
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 8, 1))
    @teller = create_operator_with_credential!(role: "teller", username: "branch-cash-html")
    @operating_unit = Organization::Services::DefaultOperatingUnit.branch!

    @vault = Cash::Commands::CreateLocation.call(
      location_type: Cash::Models::CashLocation::TYPE_BRANCH_VAULT,
      operating_unit: @operating_unit,
      name: "Branch HTML Vault"
    )
    @drawer = Cash::Commands::CreateLocation.call(
      location_type: Cash::Models::CashLocation::TYPE_TELLER_DRAWER,
      operating_unit: @operating_unit,
      drawer_code: "BHTML",
      name: "Branch HTML Drawer"
    )

    Cash::Commands::RecordCashCount.call(
      cash_location_id: @vault.id,
      counted_amount_minor_units: 10_000,
      actor_id: @teller.id,
      idempotency_key: "branch-cash-html-count-seed",
      business_date: Date.new(2026, 8, 1)
    )
  end

  test "branch cash pages render shared internal grammar" do
    internal_login!(username: "branch-cash-html")

    get branch_cash_path
    assert_response :success
    assert_includes response.body, "Cash position"
    assert_includes response.body, "Location balances"
    assert_includes response.body, @vault.name

    get branch_new_cash_transfer_path
    assert_response :success
    assert_includes response.body, "Transfer cash"
    assert_includes response.body, "Transfer request"

    get branch_new_cash_count_path
    assert_response :success
    assert_includes response.body, "Record cash count"
    assert_includes response.body, "Count request"

    get branch_cash_location_path(@vault)
    assert_response :success
    assert_includes response.body, @vault.name
    assert_includes response.body, "Recent movements"
    assert_includes response.body, "Recent counts and variances"
  end
end
