# frozen_string_literal: true

require "test_helper"

class CoreOperationalEventsRecordEventTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 22))
    @party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Pat", last_name: "Lee")
    @account = Accounts::Commands::OpenAccount.call(party_record_id: @party.id)
    @teller_session = Teller::Commands::OpenSession.call(drawer_code: "record-event-test-#{SecureRandom.hex(4)}")
  end

  test "creates pending deposit.accepted with source_account_id" do
    r = record_deposit!(idempotency_key: "idem-1", amount: 50_00)
    assert_equal :created, r[:outcome]
    ev = r[:event]
    assert_equal "pending", ev.status
    assert_equal "deposit.accepted", ev.event_type
    assert_equal @account.id, ev.source_account_id
    assert_equal 50_00, ev.amount_minor_units
    assert_equal "teller", ev.channel
  end

  test "replay returns same row when fingerprint matches" do
    a = record_deposit!(idempotency_key: "idem-replay", amount: 10_00)
    b = record_deposit!(idempotency_key: "idem-replay", amount: 10_00)
    assert_equal :created, a[:outcome]
    assert_equal :replay, b[:outcome]
    assert_equal a[:event].id, b[:event].id
  end

  test "mismatch on same idempotency key raises with fingerprint" do
    record_deposit!(idempotency_key: "idem-mix", amount: 10_00)
    err = assert_raises(Core::OperationalEvents::Commands::RecordEvent::MismatchedIdempotency) do
      record_deposit!(idempotency_key: "idem-mix", amount: 11_00)
    end
    assert_predicate err.fingerprint, :present?
  end

  test "mismatch when same idempotency key replayed with different teller_session_id" do
    other = Teller::Commands::OpenSession.call(drawer_code: "other-#{SecureRandom.hex(4)}")
    record_deposit!(idempotency_key: "idem-session", amount: 10_00, teller_session_id: @teller_session.id)
    assert_raises(Core::OperationalEvents::Commands::RecordEvent::MismatchedIdempotency) do
      record_deposit!(idempotency_key: "idem-session", amount: 10_00, teller_session_id: other.id)
    end
  end

  test "deposit without teller_session_id raises when require_open_session_for_cash is true" do
    err = assert_raises(Core::OperationalEvents::Commands::RecordEvent::InvalidRequest) do
      Core::OperationalEvents::Commands::RecordEvent.call(
        event_type: "deposit.accepted",
        channel: "teller",
        idempotency_key: "no-session-#{SecureRandom.hex(4)}",
        amount_minor_units: 100,
        currency: "USD",
        source_account_id: @account.id,
        teller_session_id: nil
      )
    end
    assert_match(/teller_session_id/i, err.message)
  end

  test "deposit without teller_session_id allowed when require_open_session_for_cash is false" do
    prior = Rails.application.config.x.teller.require_open_session_for_cash
    Rails.application.config.x.teller.require_open_session_for_cash = false
    r = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "teller",
      idempotency_key: "gate-off-#{SecureRandom.hex(4)}",
      amount_minor_units: 100,
      currency: "USD",
      source_account_id: @account.id
    )
    assert_equal :created, r[:outcome]
  ensure
    Rails.application.config.x.teller.require_open_session_for_cash = prior
  end

  test "posted replay raises" do
    r = record_deposit!(idempotency_key: "idem-posted", amount: 5_00)
    Core::Posting::Commands::PostEvent.call(operational_event_id: r[:event].id)
    assert_raises(Core::OperationalEvents::Commands::RecordEvent::PostedReplay) do
      record_deposit!(idempotency_key: "idem-posted", amount: 5_00)
    end
  end

  test "rejects invalid channel" do
    assert_raises(Core::OperationalEvents::Commands::RecordEvent::InvalidRequest) do
      Core::OperationalEvents::Commands::RecordEvent.call(
        event_type: "deposit.accepted",
        channel: "legacy",
        idempotency_key: "x",
        amount_minor_units: 1,
        currency: "USD",
        source_account_id: @account.id
      )
    end
  end

  test "requires amount and currency and source account for deposit" do
    assert_raises(Core::OperationalEvents::Commands::RecordEvent::InvalidRequest) do
      Core::OperationalEvents::Commands::RecordEvent.call(
        event_type: "deposit.accepted",
        channel: "teller",
        idempotency_key: "a",
        amount_minor_units: nil,
        currency: "USD",
        source_account_id: @account.id
      )
    end
  end

  test "rejects explicit business_date not equal to current open day" do
    assert_raises(Core::OperationalEvents::Commands::RecordEvent::InvalidRequest) do
      Core::OperationalEvents::Commands::RecordEvent.call(
        event_type: "deposit.accepted",
        channel: "batch",
        idempotency_key: "bad-bd-#{SecureRandom.hex(4)}",
        amount_minor_units: 100,
        currency: "USD",
        source_account_id: @account.id,
        business_date: Date.new(2026, 4, 21)
      )
    end
  end

  private

  def record_deposit!(idempotency_key:, amount:, teller_session_id: @teller_session.id)
    Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "teller",
      idempotency_key: idempotency_key,
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: @account.id,
      teller_session_id: teller_session_id
    )
  end
end
