# frozen_string_literal: true

require "test_helper"

class CoreOperationalEventsRecordEventInterestTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 22))
    party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Int", last_name: "Acct")
    @account = Accounts::Commands::OpenAccount.call(party_record_id: party.id)
  end

  test "interest.accrued and interest.posted require system channel" do
    assert_raises(Core::OperationalEvents::Commands::RecordEvent::InvalidRequest) do
      record_interest_accrued!(channel: "teller")
    end

    accrued = record_interest_accrued!
    Core::Posting::Commands::PostEvent.call(operational_event_id: accrued.id)

    assert_raises(Core::OperationalEvents::Commands::RecordEvent::InvalidRequest) do
      record_interest_posted!(accrued, channel: "batch")
    end
  end

  test "interest.posted requires a posted interest.accrued reference" do
    accrued = record_interest_accrued!

    err = assert_raises(Core::OperationalEvents::Commands::RecordEvent::InvalidRequest) do
      record_interest_posted!(accrued)
    end
    assert_match(/posted interest\.accrued/i, err.message)
  end

  test "interest.posted rejects wrong reference type" do
    deposit = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "batch",
      idempotency_key: "dep-ref-#{SecureRandom.hex(4)}",
      amount_minor_units: 100,
      currency: "USD",
      source_account_id: @account.id
    )[:event]
    Core::Posting::Commands::PostEvent.call(operational_event_id: deposit.id)

    err = assert_raises(Core::OperationalEvents::Commands::RecordEvent::InvalidRequest) do
      record_interest_posted!(deposit)
    end
    assert_match(/posted interest\.accrued/i, err.message)
  end

  test "interest.posted rejects amount mismatch" do
    accrued = record_interest_accrued!(amount: 123)
    Core::Posting::Commands::PostEvent.call(operational_event_id: accrued.id)

    err = assert_raises(Core::OperationalEvents::Commands::RecordEvent::InvalidRequest) do
      record_interest_posted!(accrued, amount: 124)
    end
    assert_match(/match original accrual/i, err.message)
  end

  test "interest.posted rejects duplicate payout for same accrual" do
    accrued = record_interest_accrued!
    Core::Posting::Commands::PostEvent.call(operational_event_id: accrued.id)
    record_interest_posted!(accrued)

    err = assert_raises(Core::OperationalEvents::Commands::RecordEvent::InvalidRequest) do
      record_interest_posted!(accrued)
    end
    assert_match(/already recorded/i, err.message)
  end

  test "interest.posted idempotency includes reference_id" do
    accrued_a = record_interest_accrued!(amount: 200)
    Core::Posting::Commands::PostEvent.call(operational_event_id: accrued_a.id)
    accrued_b = record_interest_accrued!(amount: 200)
    Core::Posting::Commands::PostEvent.call(operational_event_id: accrued_b.id)

    idem = "interest-post-idem-#{SecureRandom.hex(4)}"
    Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "interest.posted",
      channel: "system",
      idempotency_key: idem,
      amount_minor_units: 200,
      currency: "USD",
      source_account_id: @account.id,
      reference_id: accrued_a.id.to_s
    )

    assert_raises(Core::OperationalEvents::Commands::RecordEvent::MismatchedIdempotency) do
      Core::OperationalEvents::Commands::RecordEvent.call(
        event_type: "interest.posted",
        channel: "system",
        idempotency_key: idem,
        amount_minor_units: 200,
        currency: "USD",
        source_account_id: @account.id,
        reference_id: accrued_b.id.to_s
      )
    end
  end

  private

  def record_interest_accrued!(amount: 123, channel: "system")
    Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "interest.accrued",
      channel: channel,
      idempotency_key: "interest-accrued-#{SecureRandom.hex(4)}",
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: @account.id
    )[:event]
  end

  def record_interest_posted!(accrued, amount: accrued.amount_minor_units, channel: "system")
    Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "interest.posted",
      channel: channel,
      idempotency_key: "interest-posted-#{SecureRandom.hex(4)}",
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: @account.id,
      reference_id: accrued.id.to_s
    )[:event]
  end
end
