# frozen_string_literal: true

require "test_helper"

class CheckDepositAcceptedIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 22))

    @party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "H", last_name: "Ttp")
    @account = Accounts::Commands::OpenAccount.call(party_record_id: @party.id)
    @teller_operator, _supervisor = create_workspace_operators!
    @cash_session_id = Teller::Commands::OpenSession.call(drawer_code: "chk-http-#{SecureRandom.hex(4)}").id
  end

  test "POST operational_events accepts check deposit via orchestration with summary on index" do
    idem = "chk-http-#{SecureRandom.hex(6)}"
    hold_idem = "#{idem}-hold"
    body = {
      operational_event: {
        event_type: "check.deposit.accepted",
        channel: "teller",
        idempotency_key: idem,
        amount_minor_units: 750,
        currency: "USD",
        source_account_id: @account.id,
        teller_session_id: @cash_session_id,
        hold_amount_minor_units: 750,
        hold_idempotency_key: hold_idem,
        payload: {
          items: [
            { amount_minor_units: 400, item_reference: "REF-A", classification: "on_us" },
            { amount_minor_units: 350, serial_number: "SER-B" }
          ]
        }
      }
    }

    post "/teller/operational_events", params: body.to_json, headers: teller_json_headers(@teller_operator)
    assert_response :created
    parsed = response.parsed_body
    assert_equal "posted", parsed["posting_outcome"]
    assert_equal "created", parsed["hold_outcome"]
    ev_id = parsed["operational_event_id"]

    get "/teller/operational_events", params: { business_date: "2026-04-22" }, headers: teller_json_headers(@teller_operator)
    assert_response :success
    row = response.parsed_body.fetch("events").find { |e| e["id"] == ev_id }
    assert row["payload_summary"].present?
    assert_equal 2, row["payload_summary"]["items_count"]
    assert_nil row["payload"]
    refute row.key?("items")
  end

  test "GET event_types includes check deposit with teller-only channels" do
    get "/teller/event_types", headers: teller_json_headers(@teller_operator)
    assert_response :success
    chk = response.parsed_body.fetch("event_types").find { |h| h["event_type"] == "check.deposit.accepted" }
    assert chk
    assert_equal %w[teller], chk["allowed_channels"]
    assert_equal "AcceptCheckDeposit", chk["record_command"]
    assert_equal true, chk["posts_to_gl"]
    assert_equal "docs/operational_events/check-deposit-accepted.md", chk["payload_schema"]
  end
end
