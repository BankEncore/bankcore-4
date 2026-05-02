# frozen_string_literal: true

require "test_helper"

class IntegrationAchIngestReceiptFileTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 25))

    @party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Ava", last_name: "Ach")
    @account = Accounts::Commands::OpenAccount.call(party_record_id: @party.id)
  end

  test "posts a valid ACH credit item with reconciliation evidence" do
    result = ingest!(item_id: "trace-001", amount_minor_units: 12_500)

    assert_equal Date.new(2026, 4, 25), result.business_date
    assert_equal({ posted: 1 }, result.counts)
    row = result.outcomes.sole
    assert_equal :posted, row.fetch(:outcome)
    assert_equal @account.account_number, row.fetch(:account_number)
    assert_equal @account.id, row.fetch(:deposit_account_id)
    assert row.fetch(:operational_event_id)
    assert row.fetch(:posting_batch_id)
    assert row.fetch(:journal_entry_id)
    assert_equal "ach:file-20260425-001:batch-1:trace-001", row.fetch(:reference_id)
    assert_equal "ach-credit-received:file-20260425-001:batch-1:trace-001", row.fetch(:idempotency_key)

    event = Core::OperationalEvents::Models::OperationalEvent.find(row.fetch(:operational_event_id))
    assert_equal "ach.credit.received", event.event_type
    assert_equal "posted", event.status
    assert_equal "batch", event.channel
    lines = event.posting_batches.sole.journal_entries.sole.journal_lines.order(:sequence_no)
    assert_equal "1120", lines.first.gl_account.account_number
    assert_equal "debit", lines.first.side
    assert_nil lines.first.deposit_account_id
    assert_equal "2110", lines.second.gl_account.account_number
    assert_equal "credit", lines.second.side
    assert_equal @account.id, lines.second.deposit_account_id
  end

  test "preserves exact account number string in lookup and outcome evidence" do
    result = ingest!(item_id: "trace-leading-zero")

    assert_equal :posted, result.outcomes.sole.fetch(:outcome)
    assert_equal @account.account_number, result.outcomes.sole.fetch(:account_number)
  end

  test "returns account-not-found and account-closed outcomes" do
    closed_party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Closed", last_name: "Ach")
    closed = Accounts::Commands::OpenAccount.call(party_record_id: closed_party.id)
    closed.update!(status: Accounts::Models::DepositAccount::STATUS_CLOSED)

    result = Integration::Ach::Commands::IngestReceiptFile.call(
      file_id: "file-20260425-002",
      batches: [
        {
          batch_id: "batch-1",
          items: [
            ach_item(item_id: "missing", account_number: "000000000000"),
            ach_item(item_id: "closed", account_number: closed.account_number)
          ]
        }
      ]
    )

    assert_equal({ account_not_found: 1, account_closed: 1 }, result.counts)
    assert_equal :account_not_found, result.outcomes.first.fetch(:outcome)
    assert_equal :account_closed, result.outcomes.second.fetch(:outcome)
    assert_equal closed.id, result.outcomes.second.fetch(:deposit_account_id)
  end

  test "idempotent replay returns already posted without duplicate journals" do
    first = ingest!(item_id: "replay-001")
    event_id = first.outcomes.sole.fetch(:operational_event_id)

    second = ingest!(item_id: "replay-001")

    assert_equal :already_posted, second.outcomes.sole.fetch(:outcome)
    assert_equal event_id, second.outcomes.sole.fetch(:operational_event_id)
    event = Core::OperationalEvents::Models::OperationalEvent.find(event_id)
    assert_equal 1, event.posting_batches.count
    assert_equal 1, event.journal_entries.count
  end

  test "mismatched replay returns idempotency mismatch" do
    ingest!(item_id: "mismatch-001", amount_minor_units: 1_00)

    result = ingest!(item_id: "mismatch-001", amount_minor_units: 2_00)

    assert_equal :idempotency_mismatch, result.outcomes.sole.fetch(:outcome)
    assert_equal 1, Core::OperationalEvents::Models::OperationalEvent.where(idempotency_key: "ach-credit-received:file-20260425-001:batch-1:mismatch-001").count
  end

  test "preview validates without creating events or journals" do
    before_events = Core::OperationalEvents::Models::OperationalEvent.count
    before_entries = Core::Ledger::Models::JournalEntry.count

    result = ingest!(item_id: "preview-001", preview: true)

    assert_equal :posted, result.outcomes.sole.fetch(:outcome)
    assert_nil result.outcomes.sole.fetch(:operational_event_id)
    assert_equal before_events, Core::OperationalEvents::Models::OperationalEvent.count
    assert_equal before_entries, Core::Ledger::Models::JournalEntry.count
  end

  test "one invalid item does not block another valid item" do
    result = Integration::Ach::Commands::IngestReceiptFile.call(
      file_id: "file-20260425-003",
      batches: [
        {
          batch_id: "batch-1",
          items: [
            ach_item(item_id: "bad-amount", amount_minor_units: 0),
            ach_item(item_id: "valid-after-bad")
          ]
        }
      ]
    )

    assert_equal({ invalid_item: 1, posted: 1 }, result.counts)
    assert_equal :invalid_item, result.outcomes.first.fetch(:outcome)
    assert_equal :posted, result.outcomes.second.fetch(:outcome)
  end

  test "posting failure leaves a pending event visible to support" do
    ach_settlement = Core::Ledger::Models::GlAccount.find_by!(account_number: "1120")
    ach_settlement.update_column(:account_number, "1120-missing")

    result = ingest!(item_id: "posting-failure")

    assert_equal :posting_failed, result.outcomes.sole.fetch(:outcome)
    event = Core::OperationalEvents::Models::OperationalEvent.find(result.outcomes.sole.fetch(:operational_event_id))
    assert_equal "pending", event.status
    assert_equal 0, event.posting_batches.count
  ensure
    ach_settlement&.update_column(:account_number, "1120")
  end

  test "structural file errors raise invalid request" do
    assert_raises(Integration::Ach::Commands::IngestReceiptFile::InvalidRequest) do
      Integration::Ach::Commands::IngestReceiptFile.call(file_id: " ", batches: [])
    end
  end

  private

  def ingest!(item_id:, amount_minor_units: 12_500, preview: false)
    Integration::Ach::Commands::IngestReceiptFile.call(
      file_id: "file-20260425-001",
      batches: [
        {
          batch_id: "batch-1",
          items: [
            ach_item(item_id: item_id, amount_minor_units: amount_minor_units)
          ]
        }
      ],
      preview: preview
    )
  end

  def ach_item(item_id:, account_number: @account.account_number, amount_minor_units: 12_500)
    {
      item_id: item_id,
      account_number: account_number,
      amount_minor_units: amount_minor_units,
      currency: "USD"
    }
  end
end
