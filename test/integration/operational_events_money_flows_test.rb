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

    record_and_post_deposit!(@account_a, 50_000, "seed-a-#{SecureRandom.hex(4)}")
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
          source_account_id: @account_a.id
        }
      }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :created
    ev_id = response.parsed_body["id"]
    post "/teller/operational_events/#{ev_id}/post", headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :created

    ev = Core::OperationalEvents::Models::OperationalEvent.find(ev_id)
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
      headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :created
    ev_id = response.parsed_body["id"]
    post "/teller/operational_events/#{ev_id}/post", headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :created

    ev = Core::OperationalEvents::Models::OperationalEvent.find(ev_id)
    lines = ev.posting_batches.sole.journal_entries.sole.journal_lines.order(:sequence_no)
    assert_equal 2, lines.size
    assert_equal @account_a.id, lines.find_by(side: "debit").deposit_account_id
    assert_equal @account_b.id, lines.find_by(side: "credit").deposit_account_id
  end

  test "reversal creates compensating journal and links entries" do
    idem = "dep-rev-#{SecureRandom.hex(6)}"
    post "/teller/operational_events",
      params: {
        operational_event: {
          event_type: "deposit.accepted",
          channel: "teller",
          idempotency_key: idem,
          amount_minor_units: 8_000,
          currency: "USD",
          source_account_id: @account_a.id
        }
      }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :created
    dep_id = response.parsed_body["id"]
    post "/teller/operational_events/#{dep_id}/post", headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :created

    post "/teller/reversals",
      params: {
        reversal: {
          original_operational_event_id: dep_id,
          channel: "teller",
          idempotency_key: "rev-#{SecureRandom.hex(6)}"
        }
      }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :created
    rev_id = response.parsed_body["id"]
    post "/teller/operational_events/#{rev_id}/post", headers: { "CONTENT_TYPE" => "application/json" }
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

  test "hold reduces available and withdrawal fails when insufficient" do
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
      headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :created

    post "/teller/operational_events",
      params: {
        operational_event: {
          event_type: "withdrawal.posted",
          channel: "teller",
          idempotency_key: "wd-big-#{SecureRandom.hex(6)}",
          amount_minor_units: 5_000,
          currency: "USD",
          source_account_id: @account_a.id
        }
      }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :unprocessable_entity
    assert_match(/insufficient/i, response.parsed_body["message"].to_s)
  end

  test "teller session open close and override record" do
    post "/teller/teller_sessions", params: {}.to_json, headers: { "CONTENT_TYPE" => "application/json" }
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
      headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :success

    post "/teller/overrides",
      params: {
        override: {
          event_type: "override.approved",
          channel: "teller",
          idempotency_key: "ovr-#{SecureRandom.hex(6)}",
          reference_id: "teller_session:#{sid}"
        }
      }.to_json,
      headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :created
    assert_equal "override.approved", Core::OperationalEvents::Models::OperationalEvent.order(:id).last.event_type
  end

  private

  def record_and_post_deposit!(account, amount, idem)
    r = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "teller",
      idempotency_key: idem,
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: account.id
    )
    Core::Posting::Commands::PostEvent.call(operational_event_id: r[:event].id)
    r[:event]
  end
end
