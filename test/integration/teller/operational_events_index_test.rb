# frozen_string_literal: true

require "test_helper"

class TellerOperationalEventsIndexTest < ActionDispatch::IntegrationTest
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 6, 1))
    @operator, = create_workspace_operators!
    @auth = teller_json_headers(@operator)
  end

  test "requires operator for index" do
    get "/teller/operational_events"
    assert_response :unauthorized
  end

  test "422 when business_date is after current" do
    get "/teller/operational_events", params: { business_date: "2026-06-15" }, headers: @auth
    assert_response :unprocessable_entity
    assert_equal "invalid_request", response.parsed_body["error"]
  end

  test "returns envelope and product context for posted deposit" do
    party_id, account_id, session_id = seed_party_account_session!

    post "/teller/operational_events",
      params: {
        operational_event: {
          event_type: "deposit.accepted",
          channel: "teller",
          idempotency_key: "idx-#{SecureRandom.hex(6)}",
          amount_minor_units: 2_000,
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

    get "/teller/operational_events", params: { business_date: "2026-06-01" }, headers: @auth
    assert_response :ok
    body = response.parsed_body
    assert_equal "2026-06-01", body["current_business_on"]
    assert_equal false, body["posting_day_closed"]
    assert_equal 1, body["events"].size
    ev = body["events"].sole
    assert_equal event_id, ev["id"]
    assert_equal "posted", ev["status"]
    src = ev["source_account"]
    assert_equal account_id, src["id"]
    assert src["deposit_product_id"].present?
    assert src["product_code"].present?
    assert src["product_name"].present?
    assert_equal 1, ev["posting_batch_ids"].size
    assert ev["journal_entry_ids"].is_a?(Array)
    assert_equal 1, ev["journal_entry_ids"].size
  end

  test "posting_day_closed true for historical business_date" do
    party_id, account_id, session_id = seed_party_account_session!
    post "/teller/operational_events",
      params: {
        operational_event: {
          event_type: "deposit.accepted",
          channel: "teller",
          idempotency_key: "hist-#{SecureRandom.hex(6)}",
          amount_minor_units: 100,
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

    supervisor = Workspace::Models::Operator.find_by!(role: "supervisor")
    sup_auth = teller_json_headers(supervisor)
    post "/teller/business_date/close", params: {}.to_json, headers: sup_auth
    assert_response :created

    get "/teller/operational_events", params: { business_date: "2026-06-01" }, headers: @auth
    assert_response :ok
    assert_equal "2026-06-02", response.parsed_body["current_business_on"]
    assert_equal true, response.parsed_body["posting_day_closed"]
  end

  private

  def seed_party_account_session!
    post "/teller/parties",
      params: { party_type: "individual", first_name: "I", last_name: "dx" }.to_json,
      headers: @auth
    assert_response :created
    party_id = response.parsed_body["id"]

    post "/teller/deposit_accounts",
      params: { deposit_account: { party_record_id: party_id } }.to_json,
      headers: @auth
    assert_response :created
    account_id = response.parsed_body["id"]

    post "/teller/teller_sessions",
      params: { drawer_code: "oe-idx-#{SecureRandom.hex(6)}" }.to_json,
      headers: @auth
    assert_response :created
    session_id = response.parsed_body["id"]

    [ party_id, account_id, session_id ]
  end
end
