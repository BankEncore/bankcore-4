# frozen_string_literal: true

require "test_helper"

class TellerQueriesClosePackageClassificationTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    BankCore::Seeds::DepositProducts.seed!
    BankCore::Seeds::OperatingUnits.seed!
    BankCore::Seeds::Rbac.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: @bd = Date.new(2026, 5, 10))
    @operating_unit = Organization::Services::DefaultOperatingUnit.branch!
    @operator = Workspace::Models::Operator.create!(
      display_name: "Classification Tester",
      role: "admin",
      active: true,
      default_operating_unit: @operating_unit
    )
    @account = open_account!
  end

  test "readiness matches direct EodReadiness call" do
    direct = Teller::Queries::EodReadiness.call(business_date: @bd)
    result = Teller::Queries::ClosePackageClassification.call(business_date: @bd)
    assert_equal direct[:eod_ready], result[:readiness][:eod_ready]
    assert_equal direct, result[:readiness]
  end

  test "actionable_close_package and retrospective_only align with posting_day_closed" do
    result = Teller::Queries::ClosePackageClassification.call(business_date: @bd)
    assert_equal false, result[:readiness][:posting_day_closed]
    assert_equal true, result[:actionable_close_package]
    assert_equal false, result[:retrospective_only]

    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 5, 11))
    past = Teller::Queries::ClosePackageClassification.call(business_date: @bd)
    assert_equal true, past[:readiness][:posting_day_closed]
    assert_equal false, past[:actionable_close_package]
    assert_equal true, past[:retrospective_only]
  end

  test "blockers mirror EodReadiness when session open" do
    session_drawer = Cash::Commands::CreateLocation.call(
      location_type: Cash::Models::CashLocation::TYPE_TELLER_DRAWER,
      operating_unit: @operating_unit,
      name: "Cls Session Drawer",
      drawer_code: "CLS-#{SecureRandom.hex(3)}"
    )
    Teller::Models::TellerSession.create!(
      status: Teller::Models::TellerSession::STATUS_OPEN,
      opened_at: Time.current,
      drawer_code: session_drawer.drawer_code,
      operating_unit: @operating_unit,
      cash_location: session_drawer
    )

    result = Teller::Queries::ClosePackageClassification.call(business_date: @bd)
    assert_equal false, result[:readiness][:eod_ready]
    codes = result[:blockers].pluck(:code)
    assert_includes codes, "open_teller_sessions"
    blocker = result[:blockers].find { |b| b[:code] == "open_teller_sessions" }
    assert blocker[:count].positive?
    assert_kind_of Array, blocker[:teller_session_ids]
  end

  test "overdraft nsf_denied is exception not posted summary" do
    oe = Core::OperationalEvents::Models::OperationalEvent.create!(
      event_type: "overdraft.nsf_denied",
      status: Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED,
      business_date: @bd,
      channel: "teller",
      idempotency_key: "cls-nsf-#{SecureRandom.hex(4)}",
      amount_minor_units: 0,
      currency: "USD",
      source_account_id: @account.id,
      actor_id: @operator.id
    )

    result = Teller::Queries::ClosePackageClassification.call(business_date: @bd)
    assert_equal 1, result[:buckets][:exception][:count]
    assert_includes result[:buckets][:exception][:operational_event_ids], oe.id
    assert_equal 0, result[:buckets][:posted][:count]
  end

  test "posting reversal bucket" do
    oe = Core::OperationalEvents::Models::OperationalEvent.create!(
      event_type: "posting.reversal",
      status: Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED,
      business_date: @bd,
      channel: "teller",
      idempotency_key: "cls-rev-#{SecureRandom.hex(4)}",
      amount_minor_units: 100,
      currency: "USD",
      source_account_id: @account.id,
      actor_id: @operator.id
    )

    result = Teller::Queries::ClosePackageClassification.call(business_date: @bd)
    assert_equal 1, result[:buckets][:reversed][:count]
    assert_includes result[:buckets][:reversed][:operational_event_ids], oe.id
    assert_equal 0, result[:buckets][:posted][:count]
  end

  test "override allowlist bucket" do
    oe = Core::OperationalEvents::Models::OperationalEvent.create!(
      event_type: "override.requested",
      status: Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED,
      business_date: @bd,
      channel: "branch",
      idempotency_key: "cls-ovr-#{SecureRandom.hex(4)}",
      amount_minor_units: 0,
      currency: "USD",
      actor_id: @operator.id
    )

    result = Teller::Queries::ClosePackageClassification.call(business_date: @bd)
    assert_equal 1, result[:buckets][:overridden][:count]
    assert_includes result[:buckets][:overridden][:operational_event_ids], oe.id
    assert_equal 0, result[:buckets][:posted][:count]
  end

  test "pending operational event bucket" do
    oe = Core::OperationalEvents::Models::OperationalEvent.create!(
      event_type: "deposit.accepted",
      status: Core::OperationalEvents::Models::OperationalEvent::STATUS_PENDING,
      business_date: @bd,
      channel: "batch",
      idempotency_key: "cls-pend-#{SecureRandom.hex(4)}",
      amount_minor_units: 500,
      currency: "USD",
      source_account_id: @account.id
    )

    result = Teller::Queries::ClosePackageClassification.call(business_date: @bd)
    assert_equal 1, result[:buckets][:pending][:count]
    assert_includes result[:buckets][:pending][:operational_event_ids], oe.id
  end

  test "posted fee assessed counts as posted" do
    oe = Core::OperationalEvents::Models::OperationalEvent.create!(
      event_type: "fee.assessed",
      status: Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED,
      business_date: @bd,
      channel: "system",
      idempotency_key: "cls-fee-#{SecureRandom.hex(4)}",
      amount_minor_units: 100,
      currency: "USD",
      source_account_id: @account.id
    )

    result = Teller::Queries::ClosePackageClassification.call(business_date: @bd)
    assert_equal 1, result[:buckets][:posted][:count]
    assert_includes result[:buckets][:posted][:operational_event_ids], oe.id
  end

  test "warnings surface cash eod readiness codes" do
    vault = Cash::Commands::CreateLocation.call(
      location_type: Cash::Models::CashLocation::TYPE_INTERNAL_TRANSIT,
      operating_unit: @operating_unit,
      name: "Cls Vault"
    )
    drawer = Cash::Commands::CreateLocation.call(
      location_type: Cash::Models::CashLocation::TYPE_TELLER_DRAWER,
      operating_unit: @operating_unit,
      name: "Cls Drawer",
      drawer_code: "CLSW-#{SecureRandom.hex(3)}"
    )
    Cash::Models::CashMovement.create!(
      source_cash_location: drawer,
      destination_cash_location: vault,
      operating_unit: @operating_unit,
      actor: @operator,
      amount_minor_units: 100,
      currency: "USD",
      business_date: @bd,
      status: Cash::Models::CashMovement::STATUS_PENDING_APPROVAL,
      movement_type: Cash::Models::CashMovement::TYPE_INTERNAL_TRANSFER,
      idempotency_key: "cls-move-#{SecureRandom.hex(4)}",
      request_fingerprint: SecureRandom.hex(16)
    )

    result = Teller::Queries::ClosePackageClassification.call(business_date: @bd)
    codes = result[:warnings].pluck(:code)
    assert_includes codes, "pending_cash_movements"
    warn = result[:warnings].find { |w| w[:code] == "pending_cash_movements" }
    assert_equal 1, warn[:count]
  end

  test "held bucket uses same day placement operational event" do
    hold_result = Accounts::Commands::PlaceHold.call(
      deposit_account_id: @account.id,
      amount_minor_units: 50,
      currency: "USD",
      channel: "branch",
      idempotency_key: "cls-hold-#{SecureRandom.hex(4)}",
      actor_id: @operator.id
    )
    hold = hold_result.fetch(:hold)

    result = Teller::Queries::ClosePackageClassification.call(business_date: @bd)
    assert_equal 1, result[:buckets][:held][:count]
    assert_includes result[:buckets][:held][:hold_ids], hold.id
  end

  test "active hold excluded when placement and link are different business dates" do
    hold_result = Accounts::Commands::PlaceHold.call(
      deposit_account_id: @account.id,
      amount_minor_units: 50,
      currency: "USD",
      channel: "branch",
      idempotency_key: "cls-hold2-#{SecureRandom.hex(4)}",
      actor_id: @operator.id
    )
    hold = hold_result.fetch(:hold)
    hold.placed_by_operational_event.update_column(:business_date, @bd - 1.day)

    result = Teller::Queries::ClosePackageClassification.call(business_date: @bd)
    assert_equal 0, result[:buckets][:held][:count]
    assert_not_includes result[:buckets][:held][:hold_ids], hold.id
  end

  private

  def open_account!
    party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Cls", last_name: SecureRandom.hex(3))
    Accounts::Commands::OpenAccount.call(party_record_id: party.id)
  end
end
