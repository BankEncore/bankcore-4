# frozen_string_literal: true

require "test_helper"

class CoreOperationalEventsRecordReversalInterestTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 22))
    party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Rev", last_name: "Interest")
    @account = Accounts::Commands::OpenAccount.call(party_record_id: party.id)
  end

  test "reverses posted interest.posted" do
    accrued = record_posted_interest_accrued!(amount: 222)
    posted = record_posted_interest_payout!(accrued, amount: 222)

    result = Core::OperationalEvents::Commands::RecordReversal.call(
      original_operational_event_id: posted.id,
      channel: "system",
      idempotency_key: "rev-interest-posted-#{SecureRandom.hex(4)}"
    )
    assert_equal :created, result[:outcome]

    reversal = result[:event]
    Core::Posting::Commands::PostEvent.call(operational_event_id: reversal.id)
    assert_equal "posting.reversal", reversal.event_type
    assert_equal posted.id, reversal.reversal_of_event_id
  end

  test "rejects reversal of interest.accrued when linked payout is posted" do
    accrued = record_posted_interest_accrued!(amount: 333)
    record_posted_interest_payout!(accrued, amount: 333)

    err = assert_raises(Core::OperationalEvents::Commands::RecordReversal::InvalidRequest) do
      Core::OperationalEvents::Commands::RecordReversal.call(
        original_operational_event_id: accrued.id,
        channel: "system",
        idempotency_key: "rev-interest-accrued-blocked-#{SecureRandom.hex(4)}"
      )
    end
    assert_match(/linked interest payout/i, err.message)
  end

  test "reverses interest.accrued when no payout exists" do
    accrued = record_posted_interest_accrued!(amount: 444)

    result = Core::OperationalEvents::Commands::RecordReversal.call(
      original_operational_event_id: accrued.id,
      channel: "system",
      idempotency_key: "rev-interest-accrued-ok-#{SecureRandom.hex(4)}"
    )
    assert_equal :created, result[:outcome]
    assert_equal accrued.id, result[:event].reversal_of_event_id
  end

  private

  def record_posted_interest_accrued!(amount:)
    accrued = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "interest.accrued",
      channel: "system",
      idempotency_key: "rev-interest-accrued-#{SecureRandom.hex(4)}",
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: @account.id
    )[:event]
    Core::Posting::Commands::PostEvent.call(operational_event_id: accrued.id)
    accrued
  end

  def record_posted_interest_payout!(accrued, amount:)
    posted = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "interest.posted",
      channel: "system",
      idempotency_key: "rev-interest-posted-#{SecureRandom.hex(4)}",
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: @account.id,
      reference_id: accrued.id.to_s
    )[:event]
    Core::Posting::Commands::PostEvent.call(operational_event_id: posted.id)
    posted
  end
end
