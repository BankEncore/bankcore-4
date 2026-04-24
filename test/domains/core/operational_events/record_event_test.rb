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

  test "fee.assessed rejects when available balance is insufficient" do
    err = assert_raises(Core::OperationalEvents::Commands::RecordEvent::InvalidRequest) do
      Core::OperationalEvents::Commands::RecordEvent.call(
        event_type: "fee.assessed",
        channel: "batch",
        idempotency_key: "fee-no-funds-#{SecureRandom.hex(4)}",
        amount_minor_units: 100,
        currency: "USD",
        source_account_id: @account.id
      )
    end
    assert_match(/insufficient/i, err.message)
  end

  test "fee.waived requires reference_id" do
    fund_batch!(@account.id, 10_000)
    assert_raises(Core::OperationalEvents::Commands::RecordEvent::InvalidRequest) do
      Core::OperationalEvents::Commands::RecordEvent.call(
        event_type: "fee.waived",
        channel: "batch",
        idempotency_key: "fee-w-no-ref-#{SecureRandom.hex(4)}",
        amount_minor_units: 100,
        currency: "USD",
        source_account_id: @account.id,
        reference_id: nil
      )
    end
  end

  test "fee.waived rejects when assessment is not yet posted" do
    fund_batch!(@account.id, 10_000)
    assessed = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "fee.assessed",
      channel: "batch",
      idempotency_key: "fee-pend-#{SecureRandom.hex(4)}",
      amount_minor_units: 200,
      currency: "USD",
      source_account_id: @account.id
    )[:event]
    assert_equal "pending", assessed.status
    err = assert_raises(Core::OperationalEvents::Commands::RecordEvent::InvalidRequest) do
      Core::OperationalEvents::Commands::RecordEvent.call(
        event_type: "fee.waived",
        channel: "batch",
        idempotency_key: "fee-w-early-#{SecureRandom.hex(4)}",
        amount_minor_units: 200,
        currency: "USD",
        source_account_id: @account.id,
        reference_id: assessed.id.to_s
      )
    end
    assert_match(/posted fee\.assessed/i, err.message)
  end

  test "fee.waived rejects duplicate waiver for same assessment" do
    fund_batch!(@account.id, 20_000)
    assessed = record_post_fee_assessed!(amount: 300)
    Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "fee.waived",
      channel: "batch",
      idempotency_key: "fee-w-1-#{SecureRandom.hex(4)}",
      amount_minor_units: 300,
      currency: "USD",
      source_account_id: @account.id,
      reference_id: assessed.id.to_s
    )
    assert_raises(Core::OperationalEvents::Commands::RecordEvent::InvalidRequest) do
      Core::OperationalEvents::Commands::RecordEvent.call(
        event_type: "fee.waived",
        channel: "batch",
        idempotency_key: "fee-w-2-#{SecureRandom.hex(4)}",
        amount_minor_units: 300,
        currency: "USD",
        source_account_id: @account.id,
        reference_id: assessed.id.to_s
      )
    end
  end

  test "fee.waived idempotency replay returns same row" do
    fund_batch!(@account.id, 25_000)
    assessed = record_post_fee_assessed!(amount: 150)
    idem = "fee-w-idem-#{SecureRandom.hex(4)}"
    a = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "fee.waived",
      channel: "batch",
      idempotency_key: idem,
      amount_minor_units: 150,
      currency: "USD",
      source_account_id: @account.id,
      reference_id: assessed.id.to_s
    )
    b = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "fee.waived",
      channel: "batch",
      idempotency_key: idem,
      amount_minor_units: 150,
      currency: "USD",
      source_account_id: @account.id,
      reference_id: assessed.id.to_s
    )
    assert_equal :created, a[:outcome]
    assert_equal :replay, b[:outcome]
    assert_equal a[:event].id, b[:event].id
  end

  private

  def fund_batch!(account_id, amount)
    ev = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "batch",
      idempotency_key: "fund-batch-#{SecureRandom.hex(6)}",
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: account_id
    )[:event]
    Core::Posting::Commands::PostEvent.call(operational_event_id: ev.id)
  end

  def record_post_fee_assessed!(amount:)
    ev = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "fee.assessed",
      channel: "batch",
      idempotency_key: "fee-ass-#{SecureRandom.hex(5)}",
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: @account.id
    )[:event]
    Core::Posting::Commands::PostEvent.call(operational_event_id: ev.id)
    ev.reload
  end

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
