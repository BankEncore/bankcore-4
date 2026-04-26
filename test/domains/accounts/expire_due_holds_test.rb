# frozen_string_literal: true

require "test_helper"

class AccountsExpireDueHoldsTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 9, 3))
    @party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Expire", last_name: SecureRandom.hex(3))
    @account = Accounts::Commands::OpenAccount.call(party_record_id: @party.id)
  end

  test "expires due active holds through hold released event" do
    due = place_hold!("due-hold", expires_on: Date.new(2026, 9, 3))
    future = place_hold!("future-hold", expires_on: Date.new(2026, 9, 4))

    results = Accounts::Commands::ExpireDueHolds.call(as_of: Date.new(2026, 9, 3))

    assert_equal [ due.id ], results.map { |result| result[:hold].id }
    assert_equal Accounts::Models::Hold::STATUS_EXPIRED, due.reload.status
    assert_equal Accounts::Models::Hold::STATUS_ACTIVE, future.reload.status
    assert_equal "hold.released", results.first[:event].event_type
    assert_equal "system", results.first[:event].channel
    assert_equal results.first[:event], due.expired_by_operational_event
    assert_equal results.first[:event], due.released_by_operational_event
  end

  test "expiration is idempotent per hold and date" do
    hold = place_hold!("idempotent-due-hold", expires_on: Date.new(2026, 9, 3))

    first = Accounts::Commands::ExpireDueHolds.expire_hold!(hold_id: hold.id, as_of: Date.new(2026, 9, 3), channel: "system")
    second = Accounts::Commands::ExpireDueHolds.expire_hold!(hold_id: hold.id, as_of: Date.new(2026, 9, 3), channel: "system")

    assert_equal :expired, first[:outcome]
    assert_nil second
    assert_equal 1, Core::OperationalEvents::Models::OperationalEvent.where(idempotency_key: "hold-expiration:#{hold.id}:2026-09-03").count
  end

  test "expired holds no longer reduce available balance" do
    fund_account!(amount: 2_000)
    place_hold!("balance-due-hold", expires_on: Date.new(2026, 9, 3))
    assert_equal 1_500, Accounts::Services::AvailableBalanceMinorUnits.call(deposit_account_id: @account.id)

    Accounts::Commands::ExpireDueHolds.call(as_of: Date.new(2026, 9, 3))

    assert_equal 2_000, Accounts::Services::AvailableBalanceMinorUnits.call(deposit_account_id: @account.id)
  end

  private

  def place_hold!(idempotency_key, expires_on:)
    Accounts::Commands::PlaceHold.call(
      deposit_account_id: @account.id,
      amount_minor_units: 500,
      currency: "USD",
      channel: "branch",
      idempotency_key: idempotency_key,
      expires_on: expires_on
    )[:hold]
  end

  def fund_account!(amount:)
    event = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "branch",
      idempotency_key: "expire-hold-funding",
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: @account.id
    )[:event]
    Core::Posting::Commands::PostEvent.call(operational_event_id: event.id)
  end
end
