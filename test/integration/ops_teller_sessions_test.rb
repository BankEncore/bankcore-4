# frozen_string_literal: true

require "test_helper"

class OpsTellerSessionsTest < ActionDispatch::IntegrationTest
  setup do
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 24))

    @ops_operator = create_operator_with_credential!(role: "operations", username: "ops-session-review")
    @teller_operator = create_operator_with_credential!(role: "teller", username: "ops-session-teller")
  end

  test "ops teller session queue renders active sessions with variance context" do
    open_session = create_session!(
      status: Teller::Models::TellerSession::STATUS_OPEN,
      drawer_code: "drawer-open",
      opened_at: Time.zone.parse("2026-04-24 09:00"),
      variance_minor_units: 0
    )
    pending_session = create_session!(
      status: Teller::Models::TellerSession::STATUS_PENDING_SUPERVISOR,
      drawer_code: "drawer-pending",
      opened_at: Time.zone.parse("2026-04-24 08:00"),
      actual_cash_minor_units: 11_250,
      expected_cash_minor_units: 10_000,
      variance_minor_units: 1_250
    )

    internal_login!(username: "ops-session-review")
    get ops_teller_sessions_path

    assert_response :success
    assert_select "h1", "Teller sessions"
    assert_includes response.body, "Session queue"
    assert_includes response.body, "Included statuses"
    assert_includes response.body, "##{open_session.id}"
    assert_includes response.body, "##{pending_session.id}"
    assert_includes response.body, "drawer-open"
    assert_includes response.body, "drawer-pending"
    assert_includes response.body, "+$12.50"
  end

  test "ops teller session detail renders operational context and cash traceability" do
    session = create_session!(
      status: Teller::Models::TellerSession::STATUS_PENDING_SUPERVISOR,
      drawer_code: "drawer-detail",
      opened_at: Time.zone.parse("2026-04-24 08:15"),
      actual_cash_minor_units: 9_875,
      expected_cash_minor_units: 10_000,
      variance_minor_units: -125
    )
    create_session_event!(session:, operator: @teller_operator)

    internal_login!(username: "ops-session-review")
    get ops_teller_session_path(session)

    assert_response :success
    assert_select "h1", "Teller session ##{session.id}"
    assert_includes response.body, "Operational context"
    assert_includes response.body, "Cash and variance"
    assert_includes response.body, @teller_operator.display_name
    assert_includes response.body, "drawer-detail"
    assert_includes response.body, "-$1.25"
  end

  private

  def create_session!(**attrs)
    Teller::Models::TellerSession.create!(
      {
        status: attrs.fetch(:status),
        opened_at: attrs.fetch(:opened_at),
        drawer_code: attrs.fetch(:drawer_code),
        expected_cash_minor_units: attrs[:expected_cash_minor_units],
        actual_cash_minor_units: attrs[:actual_cash_minor_units],
        variance_minor_units: attrs[:variance_minor_units]
      }
    )
  end

  def create_session_event!(session:, operator:)
    party = Party::Commands::CreateParty.call(
      party_type: "individual",
      first_name: "Teller",
      last_name: "Session"
    )
    account = Accounts::Commands::OpenAccount.call(party_record_id: party.id)

    Core::OperationalEvents::Models::OperationalEvent.create!(
      event_type: "deposit.accepted",
      status: Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED,
      business_date: Date.new(2026, 4, 24),
      channel: "teller",
      idempotency_key: "ops-session-event-#{SecureRandom.hex(4)}",
      amount_minor_units: 1_000,
      currency: "USD",
      source_account_id: account.id,
      teller_session_id: session.id,
      actor_id: operator.id
    )
  end
end
