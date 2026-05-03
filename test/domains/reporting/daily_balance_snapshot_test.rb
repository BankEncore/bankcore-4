# frozen_string_literal: true

require "test_helper"

class ReportingDailyBalanceSnapshotTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 5, 2))
    party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Daily", last_name: "Snapshot")
    @account = Accounts::Commands::OpenAccount.call(party_record_id: party.id)
  end

  test "validates daily snapshot shape" do
    snapshot = Reporting::Models::DailyBalanceSnapshot.new(
      account_domain: "unknown",
      account_id: @account.id,
      account_type: Reporting::Models::DailyBalanceSnapshot::ACCOUNT_TYPE_DEPOSIT_ACCOUNT,
      as_of_date: Date.new(2026, 5, 2),
      ledger_balance_minor_units: -1_00,
      hold_balance_minor_units: -1,
      available_balance_minor_units: -1_00,
      source: "unknown",
      calculation_version: 1
    )

    assert_not snapshot.valid?
    assert_includes snapshot.errors[:account_domain], "is not included in the list"
    assert_includes snapshot.errors[:source], "is not included in the list"
    assert_includes snapshot.errors[:hold_balance_minor_units], "must be greater than or equal to 0"

    snapshot.account_domain = Reporting::Models::DailyBalanceSnapshot::ACCOUNT_DOMAIN_DEPOSITS
    snapshot.source = Reporting::Models::DailyBalanceSnapshot::SOURCE_CURRENT_PROJECTION
    snapshot.hold_balance_minor_units = 0
    assert snapshot.valid?
  end

  test "reserves loan snapshot account metadata without implementing loans" do
    snapshot = Reporting::Models::DailyBalanceSnapshot.new(
      account_domain: Reporting::Models::DailyBalanceSnapshot::ACCOUNT_DOMAIN_LOANS,
      account_id: 123,
      account_type: Reporting::Models::DailyBalanceSnapshot::ACCOUNT_TYPE_DEPOSIT_ACCOUNT,
      as_of_date: Date.new(2026, 5, 2),
      ledger_balance_minor_units: -10_000,
      hold_balance_minor_units: 0,
      available_balance_minor_units: -10_000,
      source: Reporting::Models::DailyBalanceSnapshot::SOURCE_CURRENT_PROJECTION,
      calculation_version: 1
    )

    assert_not snapshot.valid?
    assert_includes snapshot.errors[:account_type], "must be loan_account for loans snapshots"

    snapshot.account_type = Reporting::Models::DailyBalanceSnapshot::ACCOUNT_TYPE_LOAN_ACCOUNT
    assert snapshot.valid?
  end

  test "deposit snapshots must use deposit account metadata" do
    snapshot = Reporting::Models::DailyBalanceSnapshot.new(
      account_domain: Reporting::Models::DailyBalanceSnapshot::ACCOUNT_DOMAIN_DEPOSITS,
      account_id: @account.id,
      account_type: Reporting::Models::DailyBalanceSnapshot::ACCOUNT_TYPE_LOAN_ACCOUNT,
      as_of_date: Date.new(2026, 5, 2),
      ledger_balance_minor_units: 0,
      hold_balance_minor_units: 0,
      available_balance_minor_units: 0,
      source: Reporting::Models::DailyBalanceSnapshot::SOURCE_CURRENT_PROJECTION,
      calculation_version: 1
    )

    assert_not snapshot.valid?
    assert_includes snapshot.errors[:account_type], "must be deposit_account for deposits snapshots"
  end

  test "materializes deposit projections into daily balance snapshots" do
    fund_account!(5_000)
    place_hold!(amount: 1_500, key: "snapshot-hold")

    result = Reporting::Commands::MaterializeDailyBalanceSnapshots.call(as_of_date: Date.new(2026, 5, 2))

    assert_equal Date.new(2026, 5, 2), result.as_of_date
    assert_equal 1, result.snapshots_materialized

    snapshot = Reporting::Models::DailyBalanceSnapshot.find_by!(
      account_domain: Reporting::Models::DailyBalanceSnapshot::ACCOUNT_DOMAIN_DEPOSITS,
      account_id: @account.id,
      as_of_date: Date.new(2026, 5, 2)
    )
    assert_equal Reporting::Models::DailyBalanceSnapshot::ACCOUNT_TYPE_DEPOSIT_ACCOUNT, snapshot.account_type
    assert_equal 5_000, snapshot.ledger_balance_minor_units
    assert_equal 1_500, snapshot.hold_balance_minor_units
    assert_equal 3_500, snapshot.available_balance_minor_units
    assert_nil snapshot.collected_balance_minor_units
    assert_equal Reporting::Models::DailyBalanceSnapshot::SOURCE_CURRENT_PROJECTION, snapshot.source
    assert_equal Accounts::Models::DepositAccountBalanceProjection::CURRENT_CALCULATION_VERSION, snapshot.calculation_version
  end

  test "materialization creates missing zero balance projection for open accounts" do
    assert_nil @account.deposit_account_balance_projection

    result = Reporting::Commands::MaterializeDailyBalanceSnapshots.call(as_of_date: Date.new(2026, 5, 2))

    assert_equal 1, result.snapshots_materialized
    assert_equal 0, @account.reload.deposit_account_balance_projection.ledger_balance_minor_units
    snapshot = Reporting::Models::DailyBalanceSnapshot.find_by!(account_id: @account.id)
    assert_equal 0, snapshot.ledger_balance_minor_units
    assert_equal 0, snapshot.hold_balance_minor_units
    assert_equal 0, snapshot.available_balance_minor_units
  end

  test "materialization refuses stale or drifted projections" do
    fund_account!(5_000)
    @account.deposit_account_balance_projection.update!(stale: true, stale_from_date: Date.new(2026, 5, 1))

    assert_raises(Reporting::Commands::MaterializeDailyBalanceSnapshots::ProjectionDriftDetected) do
      Reporting::Commands::MaterializeDailyBalanceSnapshots.call(as_of_date: Date.new(2026, 5, 2))
    end

    assert_equal 0, Reporting::Models::DailyBalanceSnapshot.count
  end

  test "materialization is idempotent and refreshes existing snapshot values" do
    fund_account!(5_000)
    Reporting::Commands::MaterializeDailyBalanceSnapshots.call(as_of_date: Date.new(2026, 5, 2))
    snapshot = Reporting::Models::DailyBalanceSnapshot.find_by!(account_id: @account.id)
    snapshot.update!(ledger_balance_minor_units: 1, available_balance_minor_units: 1)

    result = Reporting::Commands::MaterializeDailyBalanceSnapshots.call(as_of_date: "2026-05-02")

    assert_equal 1, result.snapshots_materialized
    assert_equal 1, Reporting::Models::DailyBalanceSnapshot.where(account_id: @account.id).count
    snapshot.reload
    assert_equal 5_000, snapshot.ledger_balance_minor_units
    assert_equal 5_000, snapshot.available_balance_minor_units
  end

  private

  def fund_account!(amount)
    event = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "batch",
      idempotency_key: "daily-snapshot-fund-#{SecureRandom.hex(4)}",
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: @account.id
    ).fetch(:event)
    Core::Posting::Commands::PostEvent.call(operational_event_id: event.id)
  end

  def place_hold!(amount:, key:)
    Accounts::Commands::PlaceHold.call(
      deposit_account_id: @account.id,
      amount_minor_units: amount,
      currency: "USD",
      channel: "api",
      idempotency_key: key,
      hold_type: Accounts::Models::Hold::HOLD_TYPE_ADMINISTRATIVE,
      reason_code: Accounts::Models::Hold::REASON_MANUAL_REVIEW,
      expires_on: Date.new(2026, 5, 5)
    )
  end
end
