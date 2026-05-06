# frozen_string_literal: true

require "test_helper"

class OpsCashTest < ActionDispatch::IntegrationTest
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    @business_date = Date.new(2026, 8, 1)
    Core::BusinessDate::Commands::SetBusinessDate.call(on: @business_date)

    @ops_operator = create_operator_with_credential!(role: "operations", username: "ops-cash-review")
    @teller_operator = create_operator_with_credential!(role: "teller", username: "ops-cash-teller")
    @operating_unit = Organization::Services::DefaultOperatingUnit.branch!
  end

  test "cash approvals renders pending movement and variance queues" do
    movement, variance = seed_cash_approvals!

    internal_login!(username: "ops-cash-review")
    get ops_cash_path(reviewed_business_date: @business_date.iso8601, from_close_package: true)

    assert_response :success
    assert_select "h1", "Cash approvals"
    assert_includes response.body, "Drill context"
    assert_includes response.body, "Reviewed business date from close package"
    assert_includes response.body, "Pending movements"
    assert_includes response.body, "Pending variances"
    assert_includes response.body, "##{movement.id}"
    assert_includes response.body, "##{variance.id}"
  end

  test "cash reconciliation renders summary and method guidance" do
    seed_cash_approvals!

    internal_login!(username: "ops-cash-review")
    get ops_cash_reconciliation_path(business_date: @business_date.iso8601)

    assert_response :success
    assert_select "h1", "Cash reconciliation"
    assert_includes response.body, "Compare Cash-domain custody balances against GL 1110 evidence."
    assert_includes response.body, "Reviewed business date"
    assert_includes response.body, "Reconciliation method"
    assert_includes response.body, "Cash subledger"
    assert_includes response.body, "GL 1110"
    assert_includes response.body, "Difference"
  end

  private

  def seed_cash_approvals!
    vault = Cash::Commands::CreateLocation.call(
      location_type: Cash::Models::CashLocation::TYPE_BRANCH_VAULT,
      operating_unit: @operating_unit,
      name: "Ops Cash Vault"
    )
    drawer = Cash::Commands::CreateLocation.call(
      location_type: Cash::Models::CashLocation::TYPE_TELLER_DRAWER,
      operating_unit: @operating_unit,
      drawer_code: "OPS-CASH",
      name: "Ops Cash Drawer"
    )

    Cash::Commands::RecordCashCount.call(
      cash_location_id: vault.id,
      counted_amount_minor_units: 10_000,
      actor_id: @teller_operator.id,
      idempotency_key: "ops-cash-count-#{SecureRandom.hex(4)}",
      business_date: @business_date
    )

    movement = Cash::Commands::TransferCash.call(
      source_cash_location_id: vault.id,
      destination_cash_location_id: drawer.id,
      amount_minor_units: 2_500,
      actor_id: @teller_operator.id,
      idempotency_key: "ops-cash-movement-#{SecureRandom.hex(4)}",
      business_date: @business_date
    )
    variance = Cash::Models::CashVariance.order(:id).last

    [movement, variance]
  end
end
