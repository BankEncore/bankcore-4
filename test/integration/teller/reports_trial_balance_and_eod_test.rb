# frozen_string_literal: true

require "test_helper"

class ReportsTrialBalanceAndEodTest < ActionDispatch::IntegrationTest
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    @bd = Date.new(2026, 4, 26)
    Core::BusinessDate::Commands::SetBusinessDate.call(on: @bd)
    @teller_operator, = create_workspace_operators!
    @auth = teller_json_headers(@teller_operator)
  end

  test "trial balance and eod require operator" do
    get "/teller/reports/trial_balance", headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :unauthorized
  end

  test "invalid business_date returns unprocessable" do
    get "/teller/reports/trial_balance", params: { business_date: "not-a-date" }, headers: @auth
    assert_response :unprocessable_entity
    assert_equal "invalid_request", response.parsed_body["error"]
  end

  test "business_date after current returns unprocessable" do
    get "/teller/reports/trial_balance", params: { business_date: (@bd + 1.day).iso8601 }, headers: @auth
    assert_response :unprocessable_entity
  end

  test "eod readiness marks past business_date as posting_day_closed" do
    get "/teller/reports/eod_readiness", params: { business_date: (@bd - 1.day).iso8601 }, headers: @auth
    assert_response :ok
    body = response.parsed_body
    assert_equal @bd.iso8601, body["current_business_on"]
    assert body["posting_day_closed"]
  end

  test "trial balance empty then populated after post" do
    get "/teller/reports/trial_balance", headers: @auth
    assert_response :ok
    assert_equal @bd.iso8601, response.parsed_body["business_date"]
    assert_empty response.parsed_body["rows"]

    party_id, account_id, session_id = seed_party_account_session!

    post "/teller/operational_events",
      params: {
        operational_event: {
          event_type: "deposit.accepted",
          channel: "teller",
          idempotency_key: "eod-rpt-#{SecureRandom.hex(6)}",
          amount_minor_units: 5_000,
          currency: "USD",
          source_account_id: account_id,
          teller_session_id: session_id
        }
      }.to_json,
      headers: @auth
    assert_response :created
    event_id = response.parsed_body["id"]

    post "/teller/operational_events/#{event_id}/post", headers: @auth
    assert_response :created

    get "/teller/reports/trial_balance", headers: @auth
    assert_response :ok
    rows = response.parsed_body["rows"]
    assert_equal 2, rows.size
    deb = rows.find { |r| r["account_number"] == "1110" }
    assert_equal 5_000, deb["debit_minor_units"]
    assert_equal 0, deb["credit_minor_units"]
  end

  test "eod readiness reflects open sessions and pending events" do
    party_id, account_id, session_id = seed_party_account_session!

    get "/teller/reports/eod_readiness", headers: @auth
    assert_response :ok
    body = response.parsed_body
    assert_equal @bd.iso8601, body["business_date"]
    assert_equal @bd.iso8601, body["current_business_on"]
    assert_equal false, body["posting_day_closed"]
    assert_not body["all_sessions_closed"]
    assert_equal 1, body["open_teller_sessions_count"]
    assert_not body["eod_ready"]

    post "/teller/operational_events",
      params: {
        operational_event: {
          event_type: "deposit.accepted",
          channel: "teller",
          idempotency_key: "eod-pend-#{SecureRandom.hex(6)}",
          amount_minor_units: 100,
          currency: "USD",
          source_account_id: account_id,
          teller_session_id: session_id
        }
      }.to_json,
      headers: @auth
    assert_response :created
    pending_id = response.parsed_body["id"]

    get "/teller/reports/eod_readiness", headers: @auth
    assert_response :ok
    body = response.parsed_body
    assert_equal 1, body["pending_operational_events_count"]
    assert_not body["eod_ready"]

    post "/teller/operational_events/#{pending_id}/post", headers: @auth
    assert_response :created

    get "/teller/reports/eod_readiness", headers: @auth
    assert_response :ok
    body = response.parsed_body
    assert_equal 0, body["pending_operational_events_count"]
    assert_not body["eod_ready"]

    post "/teller/teller_sessions/close",
      params: {
        teller_session_close: {
          teller_session_id: session_id,
          expected_cash_minor_units: 0,
          actual_cash_minor_units: 0
        }
      }.to_json,
      headers: @auth
    assert_response :success

    get "/teller/reports/eod_readiness", headers: @auth
    assert_response :ok
    body = response.parsed_body
    assert body["all_sessions_closed"]
    assert_equal 0, body["open_teller_sessions_count"]
    assert body["journal_totals_balanced"]
    assert body["eod_ready"]
  end

  private

  def seed_party_account_session!
    post "/teller/parties",
      params: { party_type: "individual", first_name: "R", last_name: "Eod" }.to_json,
      headers: @auth
    assert_response :created
    party_id = response.parsed_body["id"]

    post "/teller/deposit_accounts",
      params: { deposit_account: { party_record_id: party_id } }.to_json,
      headers: @auth
    assert_response :created
    account_id = response.parsed_body["id"]

    post "/teller/teller_sessions",
      params: { drawer_code: "eod-rpt-#{SecureRandom.hex(6)}" }.to_json,
      headers: @auth
    assert_response :created
    session_id = response.parsed_body["id"]

    [ party_id, account_id, session_id ]
  end
end
