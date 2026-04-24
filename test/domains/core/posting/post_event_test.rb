# frozen_string_literal: true

require "test_helper"

class CorePostingPostEventTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 22))
    party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Q", last_name: "R")
    @account = Accounts::Commands::OpenAccount.call(party_record_id: party.id)
  end

  test "posts balanced 1110/2110 and marks event posted" do
    ev = create_pending_event!(amount: 12_34)
    r = Core::Posting::Commands::PostEvent.call(operational_event_id: ev.id)
    assert_equal :posted, r[:outcome]
    assert_equal "posted", ev.reload.status
    batch = ev.posting_batches.sole
    assert_equal "posted", batch.status
    entry = batch.journal_entries.sole
    lines = entry.journal_lines.order(:sequence_no)
    assert_equal 2, lines.size
    assert_equal 12_34, lines.sum { |l| l.side == "debit" ? l.amount_minor_units : 0 }
    assert_equal 12_34, lines.sum { |l| l.side == "credit" ? l.amount_minor_units : 0 }
    assert_equal Core::Ledger::Models::GlAccount.find_by!(account_number: "1110").id, lines.find_by(side: "debit").gl_account_id
    credit = lines.find_by(side: "credit")
    assert_equal Core::Ledger::Models::GlAccount.find_by!(account_number: "2110").id, credit.gl_account_id
    assert_equal @account.id, credit.deposit_account_id
  end

  test "second post is idempotent" do
    ev = create_pending_event!(amount: 100)
    Core::Posting::Commands::PostEvent.call(operational_event_id: ev.id)
    r = Core::Posting::Commands::PostEvent.call(operational_event_id: ev.id)
    assert_equal :already_posted, r[:outcome]
    assert_equal 1, ev.reload.posting_batches.count
  end

  test "rolls back and leaves event pending when GL is missing" do
    ev = create_pending_event!(amount: 200)
    cash = Core::Ledger::Models::GlAccount.find_by!(account_number: "1110")
    prior = cash.account_number
    cash.update_column(:account_number, "1110-tmp-missing")
    assert_raises(ActiveRecord::RecordNotFound) do
      Core::Posting::Commands::PostEvent.call(operational_event_id: ev.id)
    end
    cash.update_column(:account_number, prior)
    assert_equal "pending", ev.reload.status
    assert_equal 0, ev.posting_batches.count
  end

  test "not found raises" do
    assert_raises(Core::Posting::Commands::PostEvent::NotFound) do
      Core::Posting::Commands::PostEvent.call(operational_event_id: 0)
    end
  end

  test "posts fee.assessed as Dr 2110 Cr 4510" do
    fund_account!(25_000)
    fee = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "fee.assessed",
      channel: "batch",
      idempotency_key: "fee-a-#{SecureRandom.hex(4)}",
      amount_minor_units: 500,
      currency: "USD",
      source_account_id: @account.id
    )[:event]
    Core::Posting::Commands::PostEvent.call(operational_event_id: fee.id)
    lines = fee.reload.posting_batches.sole.journal_entries.sole.journal_lines.order(:sequence_no)
    dr = lines.find_by(side: "debit")
    cr = lines.find_by(side: "credit")
    assert_equal "2110", dr.gl_account.account_number
    assert_equal @account.id, dr.deposit_account_id
    assert_equal "4510", cr.gl_account.account_number
    assert_nil cr.deposit_account_id
  end

  test "posts fee.waived as Dr 4510 Cr 2110" do
    fund_account!(30_000)
    assessed = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "fee.assessed",
      channel: "batch",
      idempotency_key: "fee-b-#{SecureRandom.hex(4)}",
      amount_minor_units: 400,
      currency: "USD",
      source_account_id: @account.id
    )[:event]
    Core::Posting::Commands::PostEvent.call(operational_event_id: assessed.id)
    waived = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "fee.waived",
      channel: "batch",
      idempotency_key: "fee-w-#{SecureRandom.hex(4)}",
      amount_minor_units: 400,
      currency: "USD",
      source_account_id: @account.id,
      reference_id: assessed.id.to_s
    )[:event]
    Core::Posting::Commands::PostEvent.call(operational_event_id: waived.id)
    lines = waived.reload.posting_batches.sole.journal_entries.sole.journal_lines.order(:sequence_no)
    dr = lines.find_by(side: "debit")
    cr = lines.find_by(side: "credit")
    assert_equal "4510", dr.gl_account.account_number
    assert_equal "2110", cr.gl_account.account_number
    assert_equal @account.id, cr.deposit_account_id
  end

  private

  def fund_account!(amount)
    ev = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "batch",
      idempotency_key: "fund-#{SecureRandom.hex(6)}",
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: @account.id
    )[:event]
    Core::Posting::Commands::PostEvent.call(operational_event_id: ev.id)
  end

  def create_pending_event!(amount:)
    Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "batch",
      idempotency_key: "post-test-#{SecureRandom.hex(6)}",
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: @account.id
    )[:event]
  end
end
