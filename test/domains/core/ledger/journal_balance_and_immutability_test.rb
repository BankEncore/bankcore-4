# frozen_string_literal: true

require "test_helper"

class JournalBalanceAndImmutabilityTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    @cash = Core::Ledger::Models::GlAccount.find_by!(account_number: "1110")
    @deposits = Core::Ledger::Models::GlAccount.find_by!(account_number: "2110")
  end

  test "balanced journal persists at transaction commit" do
    assert_nothing_raised do
      ActiveRecord::Base.transaction do
        ev = create_operational_event!
        batch = Core::Posting::Models::PostingBatch.create!(operational_event: ev, status: "posted")
        entry = create_journal_entry!(ev, batch)
        Core::Ledger::Models::JournalLine.create!(
          journal_entry: entry, sequence_no: 1, side: "debit", gl_account: @cash, amount_minor_units: 500
        )
        Core::Ledger::Models::JournalLine.create!(
          journal_entry: entry, sequence_no: 2, side: "credit", gl_account: @deposits, amount_minor_units: 500
        )
        # Deferred balance trigger: force check before outer test transaction ends.
        ActiveRecord::Base.connection.execute("SET CONSTRAINTS ALL IMMEDIATE")
      end
    end
  end

  test "unbalanced journal fails when constraints are checked" do
    assert_raises(ActiveRecord::StatementInvalid) do
      ActiveRecord::Base.transaction do
        ev = create_operational_event!
        batch = Core::Posting::Models::PostingBatch.create!(operational_event: ev, status: "posted")
        entry = create_journal_entry!(ev, batch)
        Core::Ledger::Models::JournalLine.create!(
          journal_entry: entry, sequence_no: 1, side: "debit", gl_account: @cash, amount_minor_units: 500
        )
        Core::Ledger::Models::JournalLine.create!(
          journal_entry: entry, sequence_no: 2, side: "credit", gl_account: @deposits, amount_minor_units: 100
        )
        ActiveRecord::Base.connection.execute("SET CONSTRAINTS ALL IMMEDIATE")
      end
    end
  end

  test "journal lines cannot be updated after commit" do
    line = nil
    ActiveRecord::Base.transaction do
      ev = create_operational_event!
      batch = Core::Posting::Models::PostingBatch.create!(operational_event: ev, status: "posted")
      entry = create_journal_entry!(ev, batch)
      Core::Ledger::Models::JournalLine.create!(
        journal_entry: entry, sequence_no: 1, side: "debit", gl_account: @cash, amount_minor_units: 200
      )
      line = Core::Ledger::Models::JournalLine.create!(
        journal_entry: entry, sequence_no: 2, side: "credit", gl_account: @deposits, amount_minor_units: 200
      )
    end

    assert_raises(ActiveRecord::StatementInvalid) { line.update!(amount_minor_units: 199) }
  end

  private

  def create_operational_event!
    Core::OperationalEvents::Models::OperationalEvent.create!(
      event_type: "deposit.accepted",
      status: "posted",
      business_date: Date.current,
      idempotency_key: "test-#{SecureRandom.hex(8)}",
      amount_minor_units: 500,
      currency: "USD"
    )
  end

  def create_journal_entry!(event, batch)
    Core::Ledger::Models::JournalEntry.create!(
      posting_batch: batch,
      operational_event: event,
      business_date: event.business_date,
      currency: "USD",
      narrative: "test",
      effective_at: Time.current
    )
  end
end
