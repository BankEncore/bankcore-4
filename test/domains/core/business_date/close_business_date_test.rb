# frozen_string_literal: true

require "test_helper"

class CoreBusinessDateCloseBusinessDateTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    BankCore::Seeds::DepositProducts.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 3, 1))
    @operator = Workspace::Models::Operator.create!(role: "supervisor", display_name: "Business Date Supervisor", active: true)
  end

  test "close advances when institution is eod_ready" do
    result = Core::BusinessDate::Commands::CloseBusinessDate.call(closed_by_operator_id: @operator.id)
    assert_equal Date.new(2026, 3, 2), result[:setting].current_business_on
    assert_equal Date.new(2026, 3, 1), result[:closed_on]
    ev = Core::BusinessDate::Models::BusinessDateCloseEvent.sole
    assert_equal @operator.id, ev.closed_by_operator_id
  end

  test "close materializes daily balance snapshots before advancing business date" do
    account = open_account!
    fund_account!(account, amount: 5_000)

    result = Core::BusinessDate::Commands::CloseBusinessDate.call(closed_by_operator_id: @operator.id)

    assert_equal 1, result[:daily_balance_snapshots_materialized]
    snapshot = Reporting::Models::DailyBalanceSnapshot.find_by!(
      account_domain: Reporting::Models::DailyBalanceSnapshot::ACCOUNT_DOMAIN_DEPOSITS,
      account_id: account.id,
      as_of_date: Date.new(2026, 3, 1)
    )
    assert_equal 5_000, snapshot.ledger_balance_minor_units
    assert_equal 5_000, snapshot.available_balance_minor_units
    assert_equal Date.new(2026, 3, 2), result[:setting].current_business_on
  end

  test "close does not advance when snapshot materialization detects projection drift" do
    account = open_account!
    fund_account!(account, amount: 5_000)
    account.deposit_account_balance_projection.update!(stale: true, stale_from_date: Date.new(2026, 3, 1))

    assert_raises(Reporting::Commands::MaterializeDailyBalanceSnapshots::ProjectionDriftDetected) do
      Core::BusinessDate::Commands::CloseBusinessDate.call(closed_by_operator_id: @operator.id)
    end

    assert_equal Date.new(2026, 3, 1), Core::BusinessDate::Models::BusinessDateSetting.first.current_business_on
    assert_equal 0, Core::BusinessDate::Models::BusinessDateCloseEvent.count
    assert_equal 0, Reporting::Models::DailyBalanceSnapshot.count
  end

  test "close raises when a teller session is still open" do
    Teller::Commands::OpenSession.call(drawer_code: "close-block-#{SecureRandom.hex(4)}")
    err = assert_raises(Core::BusinessDate::Errors::EodNotReady) do
      Core::BusinessDate::Commands::CloseBusinessDate.call(closed_by_operator_id: @operator.id)
    end
    assert_equal false, err.readiness[:eod_ready]
  end

  test "close raises when business_date param does not match current" do
    assert_raises(ArgumentError) do
      Core::BusinessDate::Commands::CloseBusinessDate.call(
        closed_by_operator_id: @operator.id,
        business_date: Date.new(2026, 2, 1)
      )
    end
  end

  private

  def open_account!
    party = Party::Commands::CreateParty.call(
      party_type: "individual",
      first_name: "Close",
      last_name: "Snapshot"
    )
    Accounts::Commands::OpenAccount.call(party_record_id: party.id)
  end

  def fund_account!(account, amount:)
    event = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "batch",
      idempotency_key: "close-snapshot-fund-#{SecureRandom.hex(4)}",
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: account.id
    ).fetch(:event)
    Core::Posting::Commands::PostEvent.call(operational_event_id: event.id)
  end
end
