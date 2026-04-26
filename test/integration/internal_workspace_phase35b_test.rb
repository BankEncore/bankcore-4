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

  test "ops search and close package expose support observability evidence" do
    account = open_account!
    event = Core::OperationalEvents::Models::OperationalEvent.create!(
      event_type: "fee.assessed",
      status: Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED,
      business_date: Date.new(2026, 4, 22),
      channel: "branch",
      idempotency_key: "ops-support-event",
      amount_minor_units: 125,
      currency: "USD",
      source_account_id: account.id,
      reference_id: "support-case-123",
      actor_id: @operations.id
    )

    internal_login!(username: "ops-user")

    get ops_operational_events_path(reference_id: "support-case-123")
    assert_response :success
    assert_includes response.body, "Support keys"
    assert_includes response.body, "Reference: support-case-123"
    assert_includes response.body, "Idempotency: ops-support-event"
    assert_includes response.body, "##{event.id}"

    get ops_close_package_path
    assert_response :success
    assert_includes response.body, "EOD impact evidence"
    assert_includes response.body, "By channel"
    assert_includes response.body, "branch"
    assert_includes response.body, "fee.assessed"
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

  private

  def open_account!
    party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Ops", last_name: SecureRandom.hex(3))
    Accounts::Commands::OpenAccount.call(party_record_id: party.id)
  end
end
