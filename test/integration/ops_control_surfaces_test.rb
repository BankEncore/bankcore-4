# frozen_string_literal: true

require "test_helper"

class OpsControlSurfacesTest < ActionDispatch::IntegrationTest
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    @business_date = Date.new(2026, 8, 1)
    Core::BusinessDate::Commands::SetBusinessDate.call(on: @business_date)
    @operator = create_operator_with_credential!(role: "operations", username: "ops-controls")
  end

  test "business date close previews readiness and executes close" do
    internal_login!(username: "ops-controls")

    get "/ops/business_date_close"
    assert_response :success
    assert_includes response.body, "Business date close"
    assert_includes response.body, "EOD ready"
    assert_includes response.body, "Balance projection health"

    post "/ops/business_date_close", params: { business_date: @business_date.iso8601 }
    assert_redirected_to "/ops/business_date_close"
    assert_equal @business_date + 1.day, Core::BusinessDate::Services::CurrentBusinessDate.call
  end

  test "balance projection health page is read-only by default" do
    seed_fee_eligible_account!

    internal_login!(username: "ops-controls")
    get "/ops"
    assert_response :success
    assert_includes response.body, "Balance projections"

    get "/ops/balance_projections"
    assert_response :success
    assert_includes response.body, "Balance projection health"
    assert_includes response.body, "Stale projections"
    assert_includes response.body, "Recent rebuild evidence"
    assert_no_match(/Mark stale/, response.body)
    assert_no_match(/Rebuild projection/, response.body)
  end

  test "balance projection account detail can mark stale and rebuild one account" do
    account = seed_fee_eligible_account!
    account.deposit_account_balance_projection.update!(
      ledger_balance_minor_units: 1,
      available_balance_minor_units: 1
    )

    internal_login!(username: "ops-controls")
    get "/ops/balance_projections", params: { account: account.account_number }
    assert_response :success
    assert_includes response.body, account.account_number
    assert_includes response.body, "Drifted"
    assert_includes response.body, "Mark stale"

    assert_difference -> { Accounts::Models::DepositBalanceRebuildRequest.where(status: "requested").count }, 1 do
      post "/ops/balance_projections/#{account.id}/mark_stale"
    end
    assert_redirected_to "/ops/balance_projections?account=#{account.account_number}"
    assert account.deposit_account_balance_projection.reload.stale

    assert_difference -> { Accounts::Models::DepositBalanceRebuildRequest.where(status: "completed").count }, 1 do
      post "/ops/balance_projections/#{account.id}/rebuild"
    end
    assert_redirected_to "/ops/balance_projections?account=#{account.account_number}"
    assert_not account.deposit_account_balance_projection.reload.stale
  end

  test "balance projection repair actions require reconciliation capability" do
    account = seed_fee_eligible_account!
    create_operator_with_credential!(role: "admin", username: "ops-balance-admin")

    internal_login!(username: "ops-balance-admin")
    get "/ops/balance_projections"
    assert_response :success

    post "/ops/balance_projections/#{account.id}/mark_stale"
    assert_response :forbidden
  end

  test "bulk balance repair marks version mismatches and rebuilds stale projections" do
    account = seed_fee_eligible_account!
    account.deposit_account_balance_projection.update!(calculation_version: 99, stale: false)
    Reporting::Models::DailyBalanceSnapshot.create!(
      account_domain: Reporting::Models::DailyBalanceSnapshot::ACCOUNT_DOMAIN_DEPOSITS,
      account_id: account.id,
      account_type: Reporting::Models::DailyBalanceSnapshot::ACCOUNT_TYPE_DEPOSIT_ACCOUNT,
      as_of_date: @business_date,
      ledger_balance_minor_units: 5_000,
      hold_balance_minor_units: 0,
      available_balance_minor_units: 5_000,
      source: Reporting::Models::DailyBalanceSnapshot::SOURCE_CURRENT_PROJECTION,
      calculation_version: 99
    )

    internal_login!(username: "ops-controls")
    get "/ops/balance_projections/bulk_repair"
    assert_response :success
    assert_includes response.body, "Bulk balance repair"

    post "/ops/balance_projections/bulk_repair",
      params: { bulk_repair: { action_type: "mark_projection_versions", limit: 25 } }
    assert_redirected_to "/ops/balance_projections/bulk_repair"
    assert account.deposit_account_balance_projection.reload.stale

    post "/ops/balance_projections/bulk_repair",
      params: { bulk_repair: { action_type: "mark_snapshot_versions", limit: 25 } }
    assert_redirected_to "/ops/balance_projections/bulk_repair"
    assert Reporting::Models::DailyBalanceSnapshot.find_by!(account_id: account.id).stale

    post "/ops/balance_projections/bulk_repair",
      params: { bulk_repair: { action_type: "rebuild_stale_projections", limit: 25 } }
    assert_redirected_to "/ops/balance_projections/bulk_repair"
    assert_not account.deposit_account_balance_projection.reload.stale
  end

  test "monthly maintenance engine preview has no side effects and execute posts fees" do
    account = seed_fee_eligible_account!

    internal_login!(username: "ops-controls")
    assert_no_difference -> { Core::OperationalEvents::Models::OperationalEvent.where(event_type: "fee.assessed").count } do
      get "/ops/engine_runs/monthly_maintenance_fees/new",
        params: { business_date: @business_date.iso8601, deposit_product_id: account.deposit_product_id }
      assert_response :success
      assert_includes response.body, "Preview summary"
      assert_includes response.body, "Posted"
    end

    assert_difference -> { Core::OperationalEvents::Models::OperationalEvent.where(event_type: "fee.assessed").count }, 1 do
      post "/ops/engine_runs/monthly_maintenance_fees",
        params: {
          engine_run: {
            business_date: @business_date.iso8601,
            deposit_product_id: account.deposit_product_id
          }
        }
    end
    assert_response :created
    assert_includes response.body, "Execution summary"
  end

  test "statement engine preview has no side effects and execute creates statements" do
    account = seed_statement_eligible_account!

    internal_login!(username: "ops-controls")
    assert_no_difference -> { Deposits::Models::DepositStatement.count } do
      get "/ops/engine_runs/deposit_statements/new",
        params: { business_date: @business_date.iso8601, deposit_product_id: account.deposit_product_id }
      assert_response :success
      assert_includes response.body, "Preview summary"
      assert_includes response.body, "Generated"
    end

    assert_difference -> { Deposits::Models::DepositStatement.count }, 3 do
      post "/ops/engine_runs/deposit_statements",
        params: {
          engine_run: {
            business_date: @business_date.iso8601,
            deposit_product_id: account.deposit_product_id
          }
        }
    end
    assert_response :created
  end

  test "teller variance queue approves pending session" do
    session = Teller::Commands::OpenSession.call(drawer_code: "variance-#{SecureRandom.hex(4)}")
    session.update!(opening_cash_minor_units: 10_000)
    Teller::Commands::CloseSession.call(
      teller_session_id: session.id,
      actual_cash_minor_units: 9_900
    )

    internal_login!(username: "ops-controls")
    get "/ops/teller_variances"
    assert_response :success
    assert_includes response.body, "variance-"
    assert_includes response.body, "$1.00"

    post "/ops/teller_variances/#{session.id}/approve"
    assert_redirected_to "/ops/teller_variances"
    assert_equal Teller::Models::TellerSession::STATUS_CLOSED, session.reload.status
    assert_equal @operator.id, session.supervisor_operator_id
  end

  test "cash movement approval redirects when source balance is insufficient" do
    teller = create_operator_with_credential!(role: "teller", username: "ops-cash-teller")
    operating_unit = Organization::Services::DefaultOperatingUnit.branch!
    vault = Cash::Commands::CreateLocation.call(
      location_type: Cash::Models::CashLocation::TYPE_BRANCH_VAULT,
      operating_unit: operating_unit,
      name: "Ops Insufficient Vault"
    )
    drawer = Cash::Commands::CreateLocation.call(
      location_type: Cash::Models::CashLocation::TYPE_TELLER_DRAWER,
      operating_unit: operating_unit,
      drawer_code: "OPS-INSUFF",
      name: "Ops Insufficient Drawer"
    )
    movement = Cash::Commands::TransferCash.call(
      source_cash_location_id: vault.id,
      destination_cash_location_id: drawer.id,
      amount_minor_units: 2_500,
      actor_id: teller.id,
      idempotency_key: "ops-insufficient-cash-movement"
    )

    internal_login!(username: "ops-controls")
    post "/ops/cash/movements/#{movement.id}/approve"

    assert_redirected_to "/ops/cash"
    assert_equal "source cash balance is insufficient", flash[:alert]
    assert_equal Cash::Models::CashMovement::STATUS_PENDING_APPROVAL, movement.reload.status
  end

  test "ops controls remain forbidden to branch roles" do
    create_operator_with_credential!(role: "teller", username: "ops-control-teller")
    internal_login!(username: "ops-control-teller")

    get "/ops/engine_runs"
    assert_response :forbidden
  end

  private

  def seed_fee_eligible_account!
    product = create_product!
    Products::Models::DepositProductFeeRule.create!(
      deposit_product: product,
      fee_code: Products::Models::DepositProductFeeRule::FEE_CODE_MONTHLY_MAINTENANCE,
      amount_minor_units: 500,
      currency: "USD",
      status: Products::Models::DepositProductFeeRule::STATUS_ACTIVE,
      effective_on: @business_date - 1.day
    )
    account = open_account!(product)
    post_deposit!(account, 5_000)
    account
  end

  def seed_statement_eligible_account!
    product = create_product!
    Products::Models::DepositProductStatementProfile.create!(
      deposit_product: product,
      frequency: Products::Models::DepositProductStatementProfile::FREQUENCY_MONTHLY,
      cycle_day: 1,
      currency: "USD",
      status: Products::Models::DepositProductStatementProfile::STATUS_ACTIVE,
      effective_on: @business_date - 90.days
    )
    account = open_account!(product)
    account.update!(created_at: @business_date - 90.days)
    post_deposit!(account, 5_000)
    account
  end

  def create_product!
    Products::Models::DepositProduct.create!(
      product_code: "ops_ctrl_#{SecureRandom.hex(4)}",
      name: "Ops Control Product",
      status: Products::Models::DepositProduct::STATUS_ACTIVE,
      currency: "USD"
    )
  end

  def open_account!(product)
    party = Party::Commands::CreateParty.call(
      party_type: "individual",
      first_name: "Ops",
      last_name: "Control"
    )
    Accounts::Commands::OpenAccount.call(party_record_id: party.id, deposit_product_id: product.id)
  end

  def post_deposit!(account, amount_minor_units)
    session = Teller::Commands::OpenSession.call(drawer_code: "ops-control-#{SecureRandom.hex(4)}")
    event = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "teller",
      idempotency_key: "ops-control-deposit-#{SecureRandom.hex(4)}",
      amount_minor_units: amount_minor_units,
      currency: "USD",
      source_account_id: account.id,
      teller_session_id: session.id,
      actor_id: @operator.id
    )[:event]
    Core::Posting::Commands::PostEvent.call(operational_event_id: event.id)
    Teller::Commands::CloseSession.call(
      teller_session_id: session.id,
      actual_cash_minor_units: amount_minor_units
    )
  end
end
