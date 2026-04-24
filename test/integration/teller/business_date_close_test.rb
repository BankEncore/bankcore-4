# frozen_string_literal: true

require "test_helper"

class TellerBusinessDateCloseTest < ActionDispatch::IntegrationTest
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    @bd = Date.new(2026, 4, 18)
    Core::BusinessDate::Commands::SetBusinessDate.call(on: @bd)
    @teller, @supervisor = create_workspace_operators!
    @teller_auth = teller_json_headers(@teller)
    @supervisor_auth = teller_json_headers(@supervisor)
  end

  test "close is forbidden for non-supervisor" do
    post "/teller/business_date/close", params: {}.to_json, headers: @teller_auth
    assert_response :forbidden
  end

  test "supervisor closes when eod_ready and off-current business_date is rejected" do
    post "/teller/business_date/close", params: {}.to_json, headers: @supervisor_auth
    assert_response :created
    body = response.parsed_body
    assert_equal @bd.iso8601, body["closed_on"]
    assert_equal (@bd + 1.day).iso8601, body["current_business_on"]

    party_id, account_id, session_id = seed_party_account_session!

    post "/teller/operational_events",
      params: {
        operational_event: {
          event_type: "deposit.accepted",
          channel: "teller",
          idempotency_key: "post-old-bd-#{SecureRandom.hex(6)}",
          amount_minor_units: 100,
          currency: "USD",
          source_account_id: account_id,
          teller_session_id: session_id,
          business_date: @bd.iso8601
        }
      }.to_json,
      headers: @teller_auth
    assert_response :unprocessable_entity
    assert_match(/current business date/i, response.parsed_body["message"].to_s)
  end

  private

  def seed_party_account_session!
    post "/teller/parties",
      params: { party_type: "individual", first_name: "C", last_name: "Lose" }.to_json,
      headers: @teller_auth
    assert_response :created
    party_id = response.parsed_body["id"]

    post "/teller/deposit_accounts",
      params: { deposit_account: { party_record_id: party_id } }.to_json,
      headers: @teller_auth
    assert_response :created
    account_id = response.parsed_body["id"]

    post "/teller/teller_sessions",
      params: { drawer_code: "bd-close-#{SecureRandom.hex(6)}" }.to_json,
      headers: @teller_auth
    assert_response :created
    session_id = response.parsed_body["id"]

    [ party_id, account_id, session_id ]
  end
end
