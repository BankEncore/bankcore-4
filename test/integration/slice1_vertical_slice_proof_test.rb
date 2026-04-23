# frozen_string_literal: true

require "test_helper"

class Slice1VerticalSliceProofTest < ActionDispatch::IntegrationTest
  test "full teller flow: party, account, pending event, post, ledger invariants" do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 21))

    teller_operator, = create_workspace_operators!
    auth = teller_json_headers(teller_operator)

    post "/teller/parties",
      params: {
        party_type: "individual",
        first_name: "Proof",
        middle_name: "M",
        last_name: "Customer",
        name_suffix: "Sr."
      }.to_json,
      headers: auth
    assert_response :created
    party_json = response.parsed_body
    party_id = party_json["id"]
    assert_equal "Proof M Customer, Sr.", party_json["name"]

    post "/teller/deposit_accounts",
      params: { deposit_account: { party_record_id: party_id } }.to_json,
      headers: auth
    assert_response :created
    account_id = response.parsed_body["id"]
    account_number = response.parsed_body["account_number"]
    assert_equal Accounts::SLICE1_PRODUCT_CODE, response.parsed_body["product_code"]

    account = Accounts::Models::DepositAccount.find(account_id)
    assert_equal "open", account.status
    participation = account.deposit_account_parties.sole
    assert_equal party_id, participation.party_record_id
    assert_equal "owner", participation.role
    assert_equal "active", participation.status
    assert_equal Date.new(2026, 4, 21), participation.effective_on

    idem = "slice1-proof-#{SecureRandom.hex(8)}"
    post "/teller/operational_events",
      params: {
        operational_event: {
          event_type: "deposit.accepted",
          channel: "teller",
          idempotency_key: idem,
          amount_minor_units: 10_000,
          currency: "USD",
          source_account_id: account_id
        }
      }.to_json,
      headers: auth
    assert_response :created
    event_id = response.parsed_body["id"]

    event = Core::OperationalEvents::Models::OperationalEvent.find(event_id)
    assert_equal teller_operator.id, event.actor_id
    assert_equal "pending", event.status
    assert_equal "teller", event.channel
    assert_equal idem, event.idempotency_key
    assert_equal account_id, event.source_account_id
    assert_equal account.id, event.source_account.id

    post "/teller/operational_events/#{event_id}/post", headers: auth
    assert_response :created

    event.reload
    assert_equal "posted", event.status
    batch = event.posting_batches.sole
    assert_equal "posted", batch.status
    entry = batch.journal_entries.sole
    lines = entry.journal_lines.order(:sequence_no)
    debits = lines.where(side: "debit").sum(:amount_minor_units)
    credits = lines.where(side: "credit").sum(:amount_minor_units)
    assert_equal debits, credits
    assert_equal 10_000, debits
    gl_nums = lines.includes(:gl_account).map { |l| l.gl_account.account_number }.sort
    assert_equal %w[1110 2110], gl_nums
    assert_equal account_id, lines.find_by(side: "credit").deposit_account_id
    assert_equal account_number, account.account_number
  end
end
