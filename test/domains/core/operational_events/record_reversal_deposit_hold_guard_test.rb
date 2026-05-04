# frozen_string_literal: true

require "test_helper"

class RecordReversalDepositHoldGuardTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 22))

    @party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "R", last_name: "V")
    @account = Accounts::Commands::OpenAccount.call(party_record_id: @party.id)
    @cash_session_id = Teller::Commands::OpenSession.call(drawer_code: "rev-hold-#{SecureRandom.hex(4)}").id
    @supervisor = Workspace::Models::Operator.create!(role: "supervisor", display_name: "Rev Supervisor", active: true)
    @teller = Workspace::Models::Operator.create!(role: "teller", display_name: "Rev Teller", active: true)
  end

  test "rejects reversal of deposit while active deposit-linked hold exists" do
    dep = record_and_post_deposit!(25_000, "dep-rev-#{SecureRandom.hex(4)}")

    Accounts::Commands::PlaceHold.call(
      deposit_account_id: @account.id,
      amount_minor_units: 5_000,
      currency: "USD",
      channel: "teller",
      idempotency_key: "hold-rev-#{SecureRandom.hex(4)}",
      placed_for_operational_event_id: dep.id
    )

    err = assert_raises(Core::OperationalEvents::Commands::RecordReversal::InvalidRequest) do
      Core::OperationalEvents::Commands::RecordReversal.call(
        original_operational_event_id: dep.id,
        channel: "teller",
        idempotency_key: "rev-#{SecureRandom.hex(4)}",
        actor_id: @supervisor.id
      )
    end
    assert_match(/deposit-linked holds/i, err.message)
  end

  test "allows reversal after linked hold is released" do
    dep = record_and_post_deposit!(30_000, "dep-rev2-#{SecureRandom.hex(4)}")

    hold_r = Accounts::Commands::PlaceHold.call(
      deposit_account_id: @account.id,
      amount_minor_units: 3_000,
      currency: "USD",
      channel: "teller",
      idempotency_key: "hold-rev2-#{SecureRandom.hex(4)}",
      placed_for_operational_event_id: dep.id
    )

    Accounts::Commands::ReleaseHold.call(
      hold_id: hold_r[:hold].id,
      channel: "teller",
      idempotency_key: "rel-rev2-#{SecureRandom.hex(4)}",
      actor_id: @supervisor.id
    )

    r = Core::OperationalEvents::Commands::RecordReversal.call(
      original_operational_event_id: dep.id,
      channel: "teller",
      idempotency_key: "rev-ok-#{SecureRandom.hex(4)}",
      actor_id: @supervisor.id
    )
    assert_equal :created, r[:outcome]
    assert_equal "posting.reversal", r[:event].event_type
  end

  test "rejects reversal of check deposit while active deposit-linked hold exists" do
    dep = record_and_post_check_deposit!(15_000, "chk-rev-h-#{SecureRandom.hex(4)}")

    Accounts::Commands::PlaceHold.call(
      deposit_account_id: @account.id,
      amount_minor_units: 15_000,
      currency: "USD",
      channel: "teller",
      idempotency_key: "hold-chk-rev-#{SecureRandom.hex(4)}",
      placed_for_operational_event_id: dep.id
    )

    assert_raises(Core::OperationalEvents::Commands::RecordReversal::InvalidRequest) do
      Core::OperationalEvents::Commands::RecordReversal.call(
        original_operational_event_id: dep.id,
        channel: "teller",
        idempotency_key: "rev-chk-#{SecureRandom.hex(4)}",
        actor_id: @supervisor.id
      )
    end
  end

  test "teller channel reversal requires reversal capability in command" do
    dep = record_and_post_deposit!(10_000, "dep-rev-denied-#{SecureRandom.hex(4)}")

    assert_raises(Workspace::Authorization::Forbidden) do
      Core::OperationalEvents::Commands::RecordReversal.call(
        original_operational_event_id: dep.id,
        channel: "teller",
        idempotency_key: "rev-denied-#{SecureRandom.hex(4)}",
        actor_id: @teller.id
      )
    end
  end

  private

  def record_and_post_deposit!(amount, idem)
    r = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "teller",
      idempotency_key: idem,
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: @account.id,
      teller_session_id: @cash_session_id
    )
    Core::Posting::Commands::PostEvent.call(operational_event_id: r[:event].id)
    r[:event]
  end

  def record_and_post_check_deposit!(amount, idem)
    payload = { "items" => [ { "amount_minor_units" => amount, "item_reference" => "chk-rev-ref" } ] }
    r = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "check.deposit.accepted",
      channel: "teller",
      idempotency_key: idem,
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: @account.id,
      payload: payload
    )
    Core::Posting::Commands::PostEvent.call(operational_event_id: r[:event].id)
    r[:event]
  end
end
