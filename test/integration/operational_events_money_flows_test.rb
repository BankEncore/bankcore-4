# frozen_string_literal: true

require "test_helper"

class OperationalEventsMoneyFlowsTest < ActionDispatch::IntegrationTest
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 22))

    @party_a = Party::Commands::CreateParty.call(party_type: "individual", first_name: "A", last_name: "One")
    @party_b = Party::Commands::CreateParty.call(party_type: "individual", first_name: "B", last_name: "Two")
    @account_a = Accounts::Commands::OpenAccount.call(party_record_id: @party_a.id)
    @account_b = Accounts::Commands::OpenAccount.call(party_record_id: @party_b.id)

    @teller_operator, @supervisor_operator = create_workspace_operators!

    @cash_session_id = Teller::Commands::OpenSession.call(drawer_code: "money-flows-#{SecureRandom.hex(4)}").id

    record_and_post_deposit!(@account_a, 50_000, "seed-a-#{SecureRandom.hex(4)}")
  end

  test "GET event_types returns catalog including fee types" do
    get "/teller/event_types", headers: teller_json_headers(@teller_operator)
    assert_response :success
    types = response.parsed_body.fetch("event_types")
    codes = types.map { |h| h["event_type"] }
    assert_includes codes, "fee.assessed"
    assert_includes codes, "fee.waived"
    fee = types.find { |h| h["event_type"] == "fee.assessed" }
    assert fee["posts_to_gl"]
    assert_equal "fee.waived", fee["compensating_event_type"]
  end

  test "fee assessed post waive posts end to end via teller JSON" do
    idem_fee = "fee-http-#{SecureRandom.hex(6)}"
    post "/teller/operational_events",
      params: {
        operational_event: {
          event_type: "fee.assessed",
          channel: "teller",
          idempotency_key: idem_fee,
          amount_minor_units: 1_000,
          currency: "USD",
          source_account_id: @account_a.id,
          teller_session_id: @cash_session_id
        }
      }.to_json,
      headers: teller_json_headers(@teller_operator)
    assert_response :created
    fee_id = response.parsed_body["id"]
    post "/teller/operational_events/#{fee_id}/post", headers: teller_json_headers(@teller_operator)
    assert_response :created

    idem_w = "fee-w-http-#{SecureRandom.hex(6)}"
    post "/teller/operational_events",
      params: {
        operational_event: {
          event_type: "fee.waived",
          channel: "teller",
          idempotency_key: idem_w,
          amount_minor_units: 1_000,
          currency: "USD",
          source_account_id: @account_a.id,
          reference_id: fee_id.to_s
        }
      }.to_json,
      headers: teller_json_headers(@teller_operator)
    assert_response :created
    waive_id = response.parsed_body["id"]
    post "/teller/operational_events/#{waive_id}/post", headers: teller_json_headers(@teller_operator)
    assert_response :created
  end

  test "missing X-Operator-Id returns unauthorized for teller JSON" do
    post "/teller/operational_events",
      params: {
        operational_event: {
          event_type: "withdrawal.posted",
          channel: "teller",
          idempotency_key: "wd-no-op-#{SecureRandom.hex(4)}",
          amount_minor_units: 100,
          currency: "USD",
          source_account_id: @account_a.id,
          teller_session_id: @cash_session_id
        }
      }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :unauthorized
    assert_equal "unauthorized", response.parsed_body["error"]
  end

  test "withdrawal posts dr 2110 cr 1110 with subledger" do
    idem = "wd-#{SecureRandom.hex(6)}"
    post "/teller/operational_events",
      params: {
        operational_event: {
          event_type: "withdrawal.posted",
          channel: "teller",
          idempotency_key: idem,
          amount_minor_units: 5_000,
          currency: "USD",
          source_account_id: @account_a.id,
          teller_session_id: @cash_session_id
        }
      }.to_json,
      headers: teller_json_headers(@teller_operator)
    assert_response :created
    ev_id = response.parsed_body["id"]
    ev = Core::OperationalEvents::Models::OperationalEvent.find(ev_id)
    assert_equal @teller_operator.id, ev.actor_id

    post "/teller/operational_events/#{ev_id}/post", headers: teller_json_headers(@teller_operator)
    assert_response :created

    ev.reload
    lines = ev.posting_batches.sole.journal_entries.sole.journal_lines.order(:sequence_no)
    dr = lines.find_by(side: "debit")
    cr = lines.find_by(side: "credit")
    assert_equal @account_a.id, dr.deposit_account_id
    assert_nil cr.deposit_account_id
    assert_equal "2110", dr.gl_account.account_number
    assert_equal "1110", cr.gl_account.account_number
  end

  test "transfer moves balance between accounts with two 2110 subledgers" do
    record_and_post_deposit!(@account_b, 20_000, "seed-b-#{SecureRandom.hex(4)}")

    idem = "xfer-#{SecureRandom.hex(6)}"
    post "/teller/operational_events",
      params: {
        operational_event: {
          event_type: "transfer.completed",
          channel: "teller",
          idempotency_key: idem,
          amount_minor_units: 3_000,
          currency: "USD",
          source_account_id: @account_a.id,
          destination_account_id: @account_b.id
        }
      }.to_json,
      headers: teller_json_headers(@teller_operator)
    assert_response :created
    ev_id = response.parsed_body["id"]
    post "/teller/operational_events/#{ev_id}/post", headers: teller_json_headers(@teller_operator)
    assert_response :created

    ev = Core::OperationalEvents::Models::OperationalEvent.find(ev_id)
    lines = ev.posting_batches.sole.journal_entries.sole.journal_lines.order(:sequence_no)
    assert_equal 2, lines.size
    assert_equal @account_a.id, lines.find_by(side: "debit").deposit_account_id
    assert_equal @account_b.id, lines.find_by(side: "credit").deposit_account_id
  end

  test "reversal returns forbidden for teller operator" do
    idem = "dep-rev-teller-#{SecureRandom.hex(6)}"
    post "/teller/operational_events",
      params: {
        operational_event: {
          event_type: "deposit.accepted",
          channel: "teller",
          idempotency_key: idem,
          amount_minor_units: 8_000,
          currency: "USD",
          source_account_id: @account_a.id,
          teller_session_id: @cash_session_id
        }
      }.to_json,
      headers: teller_json_headers(@teller_operator)
    assert_response :created
    dep_id = response.parsed_body["id"]
    post "/teller/operational_events/#{dep_id}/post", headers: teller_json_headers(@teller_operator)
    assert_response :created

    post "/teller/reversals",
      params: {
        reversal: {
          original_operational_event_id: dep_id,
          channel: "teller",
          idempotency_key: "rev-#{SecureRandom.hex(6)}"
        }
      }.to_json,
      headers: teller_json_headers(@teller_operator)
    assert_response :forbidden
    assert_equal "forbidden", response.parsed_body["error"]
  end

  test "reversal creates compensating journal and links entries for supervisor" do
    idem = "dep-rev-#{SecureRandom.hex(6)}"
    post "/teller/operational_events",
      params: {
        operational_event: {
          event_type: "deposit.accepted",
          channel: "teller",
          idempotency_key: idem,
          amount_minor_units: 8_000,
          currency: "USD",
          source_account_id: @account_a.id,
          teller_session_id: @cash_session_id
        }
      }.to_json,
      headers: teller_json_headers(@teller_operator)
    assert_response :created
    dep_id = response.parsed_body["id"]
    post "/teller/operational_events/#{dep_id}/post", headers: teller_json_headers(@teller_operator)
    assert_response :created

    post "/teller/reversals",
      params: {
        reversal: {
          original_operational_event_id: dep_id,
          channel: "teller",
          idempotency_key: "rev-#{SecureRandom.hex(6)}"
        }
      }.to_json,
      headers: teller_json_headers(@supervisor_operator)
    assert_response :created
    rev_id = response.parsed_body["id"]
    assert_equal @supervisor_operator.id,
      Core::OperationalEvents::Models::OperationalEvent.find(rev_id).actor_id

    post "/teller/operational_events/#{rev_id}/post", headers: teller_json_headers(@supervisor_operator)
    assert_response :created

    dep = Core::OperationalEvents::Models::OperationalEvent.find(dep_id)
    rev = Core::OperationalEvents::Models::OperationalEvent.find(rev_id)
    assert_equal rev.id, dep.reversed_by_event_id
    assert_equal dep.id, rev.reversal_of_event_id

    orig_entry = dep.journal_entries.sole
    rev_entry = rev.journal_entries.sole
    assert_equal orig_entry.id, rev_entry.reverses_journal_entry_id
    assert_equal rev_entry.id, orig_entry.reversing_journal_entry_id
  end

  test "hold reduces available and withdrawal is denied NSF when insufficient" do
    post "/teller/holds",
      params: {
        hold: {
          deposit_account_id: @account_a.id,
          amount_minor_units: 49_000,
          currency: "USD",
          channel: "teller",
          idempotency_key: "hold-#{SecureRandom.hex(6)}"
        }
      }.to_json,
      headers: teller_json_headers(@teller_operator)
    assert_response :created

    post "/teller/operational_events",
      params: {
        operational_event: {
          event_type: "withdrawal.posted",
          channel: "teller",
          idempotency_key: "wd-big-#{SecureRandom.hex(6)}",
          amount_minor_units: 5_000,
          currency: "USD",
          source_account_id: @account_a.id,
          teller_session_id: @cash_session_id
        }
      }.to_json,
      headers: teller_json_headers(@teller_operator)
    assert_response :unprocessable_entity
    assert_equal "nsf_denied", response.parsed_body["error"]
    assert Core::OperationalEvents::Models::OperationalEvent.exists?(
      id: response.parsed_body["denial_event_id"],
      event_type: "overdraft.nsf_denied"
    )
  end

  test "teller session open close override requested teller override approved supervisor" do
    post "/teller/teller_sessions",
      params: { drawer_code: "override-flow-#{SecureRandom.hex(6)}" }.to_json,
      headers: teller_json_headers(@teller_operator)
    assert_response :created
    sid = response.parsed_body["id"]

    post "/teller/teller_sessions/close",
      params: {
        teller_session_close: {
          teller_session_id: sid,
          expected_cash_minor_units: 100,
          actual_cash_minor_units: 100
        }
      }.to_json,
      headers: teller_json_headers(@teller_operator)
    assert_response :success

    post "/teller/overrides",
      params: {
        override: {
          event_type: "override.requested",
          channel: "teller",
          idempotency_key: "ovr-req-#{SecureRandom.hex(6)}",
          reference_id: "teller_session:#{sid}"
        }
      }.to_json,
      headers: teller_json_headers(@teller_operator)
    assert_response :created
    assert_equal "override.requested", Core::OperationalEvents::Models::OperationalEvent.order(:id).last.event_type

    post "/teller/overrides",
      params: {
        override: {
          event_type: "override.approved",
          channel: "teller",
          idempotency_key: "ovr-app-teller-#{SecureRandom.hex(6)}",
          reference_id: "teller_session:#{sid}"
        }
      }.to_json,
      headers: teller_json_headers(@teller_operator)
    assert_response :forbidden

    post "/teller/overrides",
      params: {
        override: {
          event_type: "override.approved",
          channel: "teller",
          idempotency_key: "ovr-app-sup-#{SecureRandom.hex(6)}",
          reference_id: "teller_session:#{sid}"
        }
      }.to_json,
      headers: teller_json_headers(@supervisor_operator)
    assert_response :created
    last = Core::OperationalEvents::Models::OperationalEvent.order(:id).last
    assert_equal "override.approved", last.event_type
    assert_equal @supervisor_operator.id, last.actor_id
  end

  private

  def record_and_post_deposit!(account, amount, idem)
    r = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "teller",
      idempotency_key: idem,
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: account.id,
      teller_session_id: @cash_session_id
    )
    Core::Posting::Commands::PostEvent.call(operational_event_id: r[:event].id)
    r[:event]
  end
end
