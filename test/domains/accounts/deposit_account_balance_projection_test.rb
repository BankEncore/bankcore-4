# frozen_string_literal: true

require "test_helper"

class AccountsDepositAccountBalanceProjectionTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 5, 2))
    party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Balance", last_name: "Projection")
    @account = Accounts::Commands::OpenAccount.call(party_record_id: party.id)
  end

  test "stores one projection per deposit account with default zero balances" do
    projection = Accounts::Models::DepositAccountBalanceProjection.create!(deposit_account: @account)

    assert_equal 0, projection.ledger_balance_minor_units
    assert_equal 0, projection.hold_balance_minor_units
    assert_equal 0, projection.available_balance_minor_units
    assert_equal 1, projection.calculation_version
    assert_not projection.stale
    assert_equal projection, @account.reload.deposit_account_balance_projection
  end

  test "allows negative ledger and available balances but not negative hold totals" do
    projection = Accounts::Models::DepositAccountBalanceProjection.new(
      deposit_account: @account,
      ledger_balance_minor_units: -1_00,
      hold_balance_minor_units: -1,
      available_balance_minor_units: -1_00
    )

    assert_not projection.valid?
    assert_includes projection.errors[:hold_balance_minor_units], "must be greater than or equal to 0"

    projection.hold_balance_minor_units = 0
    assert projection.valid?
  end

  test "requires a positive calculation version" do
    projection = Accounts::Models::DepositAccountBalanceProjection.new(
      deposit_account: @account,
      calculation_version: 0
    )

    assert_not projection.valid?
    assert_includes projection.errors[:calculation_version], "must be greater than 0"
  end

  test "enforces uniqueness by deposit account" do
    Accounts::Models::DepositAccountBalanceProjection.create!(deposit_account: @account)

    duplicate = Accounts::Models::DepositAccountBalanceProjection.new(deposit_account: @account)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:deposit_account], "has already been taken"
  end

  test "place hold refreshes projection available balance" do
    fund_account!(5_000)

    result = place_hold!(amount: 1_500, key: "projection-place-hold")

    projection = @account.deposit_account_balance_projection.reload
    assert_equal 5_000, projection.ledger_balance_minor_units
    assert_equal 1_500, projection.hold_balance_minor_units
    assert_equal 3_500, projection.available_balance_minor_units
    assert_equal result.fetch(:event).id, projection.last_operational_event_id
  end

  test "release hold refreshes projection available balance" do
    fund_account!(5_000)
    hold = place_hold!(amount: 1_500, key: "projection-release-place").fetch(:hold)

    result = Accounts::Commands::ReleaseHold.call(
      hold_id: hold.id,
      channel: "api",
      idempotency_key: "projection-release-hold"
    )

    projection = @account.deposit_account_balance_projection.reload
    assert_equal 5_000, projection.ledger_balance_minor_units
    assert_equal 0, projection.hold_balance_minor_units
    assert_equal 5_000, projection.available_balance_minor_units
    assert_equal result.fetch(:event).id, projection.last_operational_event_id
  end

  test "expire due holds refreshes projection available balance" do
    fund_account!(5_000)
    place_hold!(amount: 1_500, key: "projection-expire-hold", expires_on: Date.new(2026, 5, 2))

    result = Accounts::Commands::ExpireDueHolds.call(as_of: Date.new(2026, 5, 2)).sole

    projection = @account.deposit_account_balance_projection.reload
    assert_equal 5_000, projection.ledger_balance_minor_units
    assert_equal 0, projection.hold_balance_minor_units
    assert_equal 5_000, projection.available_balance_minor_units
    assert_equal result.fetch(:event).id, projection.last_operational_event_id
  end

  private

  def fund_account!(amount)
    event = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "batch",
      idempotency_key: "projection-fund-#{SecureRandom.hex(4)}",
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: @account.id
    ).fetch(:event)
    Core::Posting::Commands::PostEvent.call(operational_event_id: event.id)
  end

  def place_hold!(amount:, key:, expires_on: Date.new(2026, 5, 5))
    Accounts::Commands::PlaceHold.call(
      deposit_account_id: @account.id,
      amount_minor_units: amount,
      currency: "USD",
      channel: "api",
      idempotency_key: key,
      hold_type: Accounts::Models::Hold::HOLD_TYPE_ADMINISTRATIVE,
      reason_code: Accounts::Models::Hold::REASON_MANUAL_REVIEW,
      expires_on: expires_on
    )
  end
end
