# frozen_string_literal: true

require "test_helper"

class AccountsPlaceHoldDepositLinkTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 22))

    @party_a = Party::Commands::CreateParty.call(party_type: "individual", first_name: "A", last_name: "One")
    @party_b = Party::Commands::CreateParty.call(party_type: "individual", first_name: "B", last_name: "Two")
    @account_a = Accounts::Commands::OpenAccount.call(party_record_id: @party_a.id)
    @account_b = Accounts::Commands::OpenAccount.call(party_record_id: @party_b.id)
    @cash_session_id = Teller::Commands::OpenSession.call(drawer_code: "ph-deposit-#{SecureRandom.hex(4)}").id
  end

  test "places hold linked to posted deposit when sum within deposit amount" do
    dep = record_and_post_deposit!(@account_a, 10_000, "dep-ph-#{SecureRandom.hex(4)}")

    r = Accounts::Commands::PlaceHold.call(
      deposit_account_id: @account_a.id,
      amount_minor_units: 4_000,
      currency: "USD",
      channel: "teller",
      idempotency_key: "hold-ph-#{SecureRandom.hex(4)}",
      placed_for_operational_event_id: dep.id
    )
    assert_equal :created, r[:outcome]
    assert_equal dep.id, r[:hold].placed_for_operational_event_id
  end

  test "allows multiple holds on same deposit when combined amount does not exceed deposit" do
    dep = record_and_post_deposit!(@account_a, 10_000, "dep-ph2-#{SecureRandom.hex(4)}")

    Accounts::Commands::PlaceHold.call(
      deposit_account_id: @account_a.id,
      amount_minor_units: 6_000,
      currency: "USD",
      channel: "teller",
      idempotency_key: "hold-a-#{SecureRandom.hex(4)}",
      placed_for_operational_event_id: dep.id
    )
    r = Accounts::Commands::PlaceHold.call(
      deposit_account_id: @account_a.id,
      amount_minor_units: 4_000,
      currency: "USD",
      channel: "teller",
      idempotency_key: "hold-b-#{SecureRandom.hex(4)}",
      placed_for_operational_event_id: dep.id
    )
    assert_equal :created, r[:outcome]
  end

  test "rejects hold when single amount exceeds deposit" do
    dep = record_and_post_deposit!(@account_a, 5_000, "dep-ph3-#{SecureRandom.hex(4)}")

    err = assert_raises(Accounts::Commands::PlaceHold::InvalidRequest) do
      Accounts::Commands::PlaceHold.call(
        deposit_account_id: @account_a.id,
        amount_minor_units: 5_001,
        currency: "USD",
        channel: "teller",
        idempotency_key: "hold-c-#{SecureRandom.hex(4)}",
        placed_for_operational_event_id: dep.id
      )
    end
    assert_match(/cannot exceed the deposit amount/i, err.message)
  end

  test "rejects hold when sum of active holds would exceed deposit" do
    dep = record_and_post_deposit!(@account_a, 10_000, "dep-ph4-#{SecureRandom.hex(4)}")

    Accounts::Commands::PlaceHold.call(
      deposit_account_id: @account_a.id,
      amount_minor_units: 6_000,
      currency: "USD",
      channel: "teller",
      idempotency_key: "hold-d1-#{SecureRandom.hex(4)}",
      placed_for_operational_event_id: dep.id
    )
    assert_raises(Accounts::Commands::PlaceHold::InvalidRequest) do
      Accounts::Commands::PlaceHold.call(
        deposit_account_id: @account_a.id,
        amount_minor_units: 5_000,
        currency: "USD",
        channel: "teller",
        idempotency_key: "hold-d2-#{SecureRandom.hex(4)}",
        placed_for_operational_event_id: dep.id
      )
    end
  end

  test "rejects linked hold when event is not deposit.accepted" do
    record_and_post_deposit!(@account_a, 50_000, "fund-wd-#{SecureRandom.hex(4)}")
    idem = "wd-ph-#{SecureRandom.hex(4)}"
    wd = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "withdrawal.posted",
      channel: "teller",
      idempotency_key: idem,
      amount_minor_units: 100,
      currency: "USD",
      source_account_id: @account_a.id,
      teller_session_id: @cash_session_id
    )
    Core::Posting::Commands::PostEvent.call(operational_event_id: wd[:event].id)

    assert_raises(Accounts::Commands::PlaceHold::InvalidRequest) do
      Accounts::Commands::PlaceHold.call(
        deposit_account_id: @account_a.id,
        amount_minor_units: 50,
        currency: "USD",
        channel: "teller",
        idempotency_key: "hold-wd-#{SecureRandom.hex(4)}",
        placed_for_operational_event_id: wd[:event].id
      )
    end
  end

  test "rejects linked hold when deposit is still pending" do
    dep = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "teller",
      idempotency_key: "dep-pend-#{SecureRandom.hex(4)}",
      amount_minor_units: 8_000,
      currency: "USD",
      source_account_id: @account_a.id,
      teller_session_id: @cash_session_id
    )[:event]

    assert_raises(Accounts::Commands::PlaceHold::InvalidRequest) do
      Accounts::Commands::PlaceHold.call(
        deposit_account_id: @account_a.id,
        amount_minor_units: 1_000,
        currency: "USD",
        channel: "teller",
        idempotency_key: "hold-pend-#{SecureRandom.hex(4)}",
        placed_for_operational_event_id: dep.id
      )
    end
  end

  test "rejects linked hold when deposit account does not match deposit source account" do
    dep = record_and_post_deposit!(@account_b, 20_000, "dep-other-#{SecureRandom.hex(4)}")

    assert_raises(Accounts::Commands::PlaceHold::InvalidRequest) do
      Accounts::Commands::PlaceHold.call(
        deposit_account_id: @account_a.id,
        amount_minor_units: 1_000,
        currency: "USD",
        channel: "teller",
        idempotency_key: "hold-mismatch-#{SecureRandom.hex(4)}",
        placed_for_operational_event_id: dep.id
      )
    end
  end

  test "idempotency replay rejects different placed_for_operational_event_id" do
    dep_a = record_and_post_deposit!(@account_a, 50_000, "dep-ida-#{SecureRandom.hex(4)}")
    dep_b = record_and_post_deposit!(@account_a, 50_000, "dep-idb-#{SecureRandom.hex(4)}")
    idem = "idem-ph-#{SecureRandom.hex(4)}"

    Accounts::Commands::PlaceHold.call(
      deposit_account_id: @account_a.id,
      amount_minor_units: 1_000,
      currency: "USD",
      channel: "teller",
      idempotency_key: idem,
      placed_for_operational_event_id: dep_a.id
    )

    assert_raises(Accounts::Commands::PlaceHold::InvalidRequest) do
      Accounts::Commands::PlaceHold.call(
        deposit_account_id: @account_a.id,
        amount_minor_units: 1_000,
        currency: "USD",
        channel: "teller",
        idempotency_key: idem,
        placed_for_operational_event_id: dep_b.id
      )
    end
  end

  private

  def record_and_post_deposit!(account, amount, idem)
    r = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "teller",
      idempotency_key: idem,
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: account.id,
      teller_session_id: @cash_session_id
    )
    Core::Posting::Commands::PostEvent.call(operational_event_id: r[:event].id)
    r[:event]
  end
end
