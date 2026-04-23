# frozen_string_literal: true

require "test_helper"

class TellerSessionCashPolicyTest < ActionDispatch::IntegrationTest
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 22))
    @party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "C", last_name: "Ash")
    @account = Accounts::Commands::OpenAccount.call(party_record_id: @party.id)
    @teller_operator, = create_workspace_operators!
    @auth = teller_json_headers(@teller_operator)
    @open_sid = open_session!
    @saved_gate = Rails.application.config.x.teller.require_open_session_for_cash
  end

  teardown do
    Rails.application.config.x.teller.require_open_session_for_cash = @saved_gate
  end

  test "teller deposit without teller_session_id returns unprocessable when gate on" do
    Rails.application.config.x.teller.require_open_session_for_cash = true
    post "/teller/operational_events",
      params: {
        operational_event: {
          event_type: "deposit.accepted",
          channel: "teller",
          idempotency_key: "cash-no-sess-#{SecureRandom.hex(6)}",
          amount_minor_units: 100,
          currency: "USD",
          source_account_id: @account.id
        }
      }.to_json,
      headers: @auth
    assert_response :unprocessable_entity
    assert_match(/teller_session_id/i, response.parsed_body["message"].to_s)
  end

  test "teller deposit with closed session returns unprocessable" do
    Rails.application.config.x.teller.require_open_session_for_cash = true
    closed_sid = open_session!
    post "/teller/teller_sessions/close",
      params: {
        teller_session_close: {
          teller_session_id: closed_sid,
          expected_cash_minor_units: 100,
          actual_cash_minor_units: 100
        }
      }.to_json,
      headers: @auth
    assert_response :success

    post "/teller/operational_events",
      params: {
        operational_event: {
          event_type: "deposit.accepted",
          channel: "teller",
          idempotency_key: "cash-closed-#{SecureRandom.hex(6)}",
          amount_minor_units: 100,
          currency: "USD",
          source_account_id: @account.id,
          teller_session_id: closed_sid
        }
      }.to_json,
      headers: @auth
    assert_response :unprocessable_entity
    assert_match(/open/i, response.parsed_body["message"].to_s)
  end

  test "teller deposit with open session succeeds when gate on" do
    Rails.application.config.x.teller.require_open_session_for_cash = true
    post "/teller/operational_events",
      params: {
        operational_event: {
          event_type: "deposit.accepted",
          channel: "teller",
          idempotency_key: "cash-ok-#{SecureRandom.hex(6)}",
          amount_minor_units: 100,
          currency: "USD",
          source_account_id: @account.id,
          teller_session_id: @open_sid
        }
      }.to_json,
      headers: @auth
    assert_response :created
  end

  test "teller deposit without session succeeds when gate off" do
    Rails.application.config.x.teller.require_open_session_for_cash = false
    post "/teller/operational_events",
      params: {
        operational_event: {
          event_type: "deposit.accepted",
          channel: "teller",
          idempotency_key: "gate-off-#{SecureRandom.hex(6)}",
          amount_minor_units: 100,
          currency: "USD",
          source_account_id: @account.id
        }
      }.to_json,
      headers: @auth
    assert_response :created
  end

  test "transfer completed teller channel without teller_session_id succeeds when gate on" do
    Rails.application.config.x.teller.require_open_session_for_cash = true
    other = Party::Commands::CreateParty.call(party_type: "individual", first_name: "D", last_name: "Other")
    acct_b = Accounts::Commands::OpenAccount.call(party_record_id: other.id)
    seed = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "teller",
      idempotency_key: "xfer-seed-#{SecureRandom.hex(6)}",
      amount_minor_units: 50_000,
      currency: "USD",
      source_account_id: @account.id,
      teller_session_id: @open_sid
    )
    Core::Posting::Commands::PostEvent.call(operational_event_id: seed[:event].id)

    post "/teller/operational_events",
      params: {
        operational_event: {
          event_type: "transfer.completed",
          channel: "teller",
          idempotency_key: "xfer-no-sess-#{SecureRandom.hex(6)}",
          amount_minor_units: 1_000,
          currency: "USD",
          source_account_id: @account.id,
          destination_account_id: acct_b.id
        }
      }.to_json,
      headers: @auth
    assert_response :created
  end

  private

  def open_session!
    post "/teller/teller_sessions",
      params: { drawer_code: "cash-policy-#{SecureRandom.hex(6)}" }.to_json,
      headers: @auth
    assert_response :created
    response.parsed_body["id"]
  end
end
