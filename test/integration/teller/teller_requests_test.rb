# frozen_string_literal: true

require "test_helper"

class TellerRequestsTest < ActionDispatch::IntegrationTest
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 22))
  end

  test "party and deposit account happy path" do
    post "/teller/parties",
      params: { party_type: "individual", first_name: "Sam", last_name: "Rivera" }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :created
    party_id = response.parsed_body["id"]

    post "/teller/deposit_accounts",
      params: { deposit_account: { party_record_id: party_id } }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :created
    assert_predicate response.parsed_body["account_number"], :present?
  end

  test "operational event idempotency and post" do
    party_id = create_party!
    account_id = open_account!(party_id)

    body = {
      operational_event: {
        event_type: "deposit.accepted",
        channel: "api",
        idempotency_key: "api-deposit-1",
        amount_minor_units: 500,
        currency: "USD",
        source_account_id: account_id
      }
    }
    post "/teller/operational_events", params: body.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :created
    event_id = response.parsed_body["id"]

    post "/teller/operational_events", params: body.to_json, headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :success
    assert_equal "replay", response.parsed_body["outcome"]

    post "/teller/operational_events/#{event_id}/post", headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :created
    assert_equal "posted", response.parsed_body["outcome"]

    post "/teller/operational_events/#{event_id}/post", headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :success
    assert_equal "already_posted", response.parsed_body["outcome"]
  end

  test "deposit account returns 404 for unknown party" do
    post "/teller/deposit_accounts",
      params: { deposit_account: { party_record_id: 0 } }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :not_found
  end

  private

  def create_party!
    post "/teller/parties",
      params: { party_type: "individual", first_name: "A", last_name: "B" }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :created
    response.parsed_body["id"]
  end

  def open_account!(party_id)
    post "/teller/deposit_accounts",
      params: { deposit_account: { party_record_id: party_id } }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :created
    response.parsed_body["id"]
  end
end
