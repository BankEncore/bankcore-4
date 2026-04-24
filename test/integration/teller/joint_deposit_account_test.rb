# frozen_string_literal: true

require "test_helper"

class TellerJointDepositAccountTest < ActionDispatch::IntegrationTest
  test "POST deposit_accounts with joint_party_record_id creates two participations and deposit still posts" do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 21))

    teller_operator, = create_workspace_operators!
    auth = teller_json_headers(teller_operator)

    post "/teller/parties",
      params: { party_type: "individual", first_name: "Primary", last_name: "Owner" }.to_json,
      headers: auth
    assert_response :created
    primary_id = response.parsed_body["id"]

    post "/teller/parties",
      params: { party_type: "individual", first_name: "Joint", last_name: "Owner" }.to_json,
      headers: auth
    assert_response :created
    joint_id = response.parsed_body["id"]

    post "/teller/deposit_accounts",
      params: { deposit_account: { party_record_id: primary_id, joint_party_record_id: joint_id } }.to_json,
      headers: auth
    assert_response :created
    account_id = response.parsed_body["id"]

    account = Accounts::Models::DepositAccount.find(account_id)
    assert_equal 2, account.deposit_account_parties.count
    roles = account.deposit_account_parties.pluck(:role).sort
    assert_equal %w[joint_owner owner], roles

    post "/teller/teller_sessions", params: {}.to_json, headers: auth
    assert_response :created
    cash_session_id = response.parsed_body["id"]

    idem = "joint-deposit-#{SecureRandom.hex(8)}"
    post "/teller/operational_events",
      params: {
        operational_event: {
          event_type: "deposit.accepted",
          channel: "teller",
          idempotency_key: idem,
          amount_minor_units: 5_000,
          currency: "USD",
          source_account_id: account_id,
          teller_session_id: cash_session_id
        }
      }.to_json,
      headers: auth
    assert_response :created
    event_id = response.parsed_body["id"]

    post "/teller/operational_events/#{event_id}/post", headers: auth
    assert_response :created
    assert_equal "posted", Core::OperationalEvents::Models::OperationalEvent.find(event_id).status
  end

  test "invalid joint same party returns 422" do
    teller_operator, = create_workspace_operators!
    auth = teller_json_headers(teller_operator)

    post "/teller/parties",
      params: { party_type: "individual", first_name: "Solo", last_name: "Party" }.to_json,
      headers: auth
    assert_response :created
    party_id = response.parsed_body["id"]

    post "/teller/deposit_accounts",
      params: { deposit_account: { party_record_id: party_id, joint_party_record_id: party_id } }.to_json,
      headers: auth
    assert_response :unprocessable_entity
    assert_equal "invalid_joint_party", response.parsed_body["error"]
  end

  test "missing joint party returns 404" do
    teller_operator, = create_workspace_operators!
    auth = teller_json_headers(teller_operator)

    post "/teller/parties",
      params: { party_type: "individual", first_name: "Only", last_name: "One" }.to_json,
      headers: auth
    assert_response :created
    party_id = response.parsed_body["id"]

    post "/teller/deposit_accounts",
      params: { deposit_account: { party_record_id: party_id, joint_party_record_id: 9_999_997 } }.to_json,
      headers: auth
    assert_response :not_found
    assert_equal "joint_party_not_found", response.parsed_body["error"]
  end
end
