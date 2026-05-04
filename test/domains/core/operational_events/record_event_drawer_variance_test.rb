# frozen_string_literal: true

require "test_helper"

class CoreOperationalEventsRecordEventDrawerVarianceTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 22))
    @saved_threshold = Rails.application.config.x.teller.variance_threshold_minor_units
    Rails.application.config.x.teller.variance_threshold_minor_units = 500
  end

  teardown do
    Rails.application.config.x.teller.variance_threshold_minor_units = @saved_threshold
  end

  test "rejects teller channel for drawer variance" do
    sid = closed_session!(variance: -50)
    err = assert_raises(Core::OperationalEvents::Commands::RecordEvent::InvalidRequest) do
      Core::OperationalEvents::Commands::RecordEvent.call(
        event_type: "teller.drawer.variance.posted",
        channel: "teller",
        idempotency_key: "drawer-variance-#{sid}",
        amount_minor_units: -50,
        currency: "USD",
        teller_session_id: sid
      )
    end
    assert_match(/channel system/i, err.message)
  end

  test "rejects when session is not closed" do
    sid = Teller::Commands::OpenSession.call(drawer_code: "dv-open-#{SecureRandom.hex(4)}").id
    assert_raises(Core::OperationalEvents::Commands::RecordEvent::InvalidRequest) do
      Core::OperationalEvents::Commands::RecordEvent.call(
        event_type: "teller.drawer.variance.posted",
        channel: "system",
        idempotency_key: "drawer-variance-#{sid}",
        amount_minor_units: -10,
        currency: "USD",
        teller_session_id: sid
      )
    end
  end

  test "rejects when amount does not match session variance" do
    sid = closed_session!(variance: -50)
    assert_raises(Core::OperationalEvents::Commands::RecordEvent::InvalidRequest) do
      Core::OperationalEvents::Commands::RecordEvent.call(
        event_type: "teller.drawer.variance.posted",
        channel: "system",
        idempotency_key: "drawer-variance-#{sid}",
        amount_minor_units: -51,
        currency: "USD",
        teller_session_id: sid
      )
    end
  end

  test "creates pending event when session closed with matching signed variance" do
    sid = closed_session!(variance: -120)
    r = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "teller.drawer.variance.posted",
      channel: "system",
      idempotency_key: "drawer-variance-#{sid}",
      amount_minor_units: -120,
      currency: "USD",
      teller_session_id: sid
    )
    assert_equal :created, r[:outcome]
    ev = r[:event]
    assert_equal "pending", ev.status
    assert_nil ev.source_account_id
    assert_equal(-120, ev.amount_minor_units)
    assert_equal sid, ev.teller_session_id
  end

  test "rejects second create with different idempotency key for same session" do
    sid = closed_session!(variance: 80)
    Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "teller.drawer.variance.posted",
      channel: "system",
      idempotency_key: "drawer-variance-#{sid}",
      amount_minor_units: 80,
      currency: "USD",
      teller_session_id: sid
    )
    assert_raises(Core::OperationalEvents::Commands::RecordEvent::InvalidRequest) do
      Core::OperationalEvents::Commands::RecordEvent.call(
        event_type: "teller.drawer.variance.posted",
        channel: "system",
        idempotency_key: "other-key-#{SecureRandom.hex(4)}",
        amount_minor_units: 80,
        currency: "USD",
        teller_session_id: sid
      )
    end
  end

  private

  def closed_session!(variance:)
    sid = Teller::Commands::OpenSession.call(drawer_code: "dv-#{SecureRandom.hex(5)}").id
    exp = 10_000
    act = exp + variance
    Teller::Models::TellerSession.find(sid).update!(opening_cash_minor_units: exp)
    Teller::Commands::CloseSession.call(
      teller_session_id: sid,
      actual_cash_minor_units: act
    )
    sid
  end
end
