# frozen_string_literal: true

require "test_helper"

class CorePostingInterestPostingTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 22))
    party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Post", last_name: "Interest")
    @account = Accounts::Commands::OpenAccount.call(party_record_id: party.id)
  end

  test "posts interest.accrued as Dr 5100 Cr 2510" do
    accrued = record_interest_accrued!(amount: 321)
    Core::Posting::Commands::PostEvent.call(operational_event_id: accrued.id)

    lines = accrued.reload.posting_batches.sole.journal_entries.sole.journal_lines.order(:sequence_no)
    dr = lines.find_by(side: "debit")
    cr = lines.find_by(side: "credit")
    assert_equal "5100", dr.gl_account.account_number
    assert_nil dr.deposit_account_id
    assert_equal "2510", cr.gl_account.account_number
    assert_equal @account.id, cr.deposit_account_id
    assert_equal 321, dr.amount_minor_units
    assert_equal 321, cr.amount_minor_units
  end

  test "posts interest.posted as Dr 2510 Cr 2110" do
    accrued = record_posted_interest_accrued!(amount: 654)
    posted = record_interest_posted!(accrued, amount: 654)
    Core::Posting::Commands::PostEvent.call(operational_event_id: posted.id)

    lines = posted.reload.posting_batches.sole.journal_entries.sole.journal_lines.order(:sequence_no)
    dr = lines.find_by(side: "debit")
    cr = lines.find_by(side: "credit")
    assert_equal "2510", dr.gl_account.account_number
    assert_equal @account.id, dr.deposit_account_id
    assert_equal "2110", cr.gl_account.account_number
    assert_equal @account.id, cr.deposit_account_id
    assert_equal 654, dr.amount_minor_units
    assert_equal 654, cr.amount_minor_units
  end

  private

  def record_posted_interest_accrued!(amount:)
    accrued = record_interest_accrued!(amount: amount)
    Core::Posting::Commands::PostEvent.call(operational_event_id: accrued.id)
    accrued
  end

  def record_interest_accrued!(amount:)
    Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "interest.accrued",
      channel: "system",
      idempotency_key: "post-interest-accrued-#{SecureRandom.hex(4)}",
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: @account.id
    )[:event]
  end

  def record_interest_posted!(accrued, amount:)
    Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "interest.posted",
      channel: "system",
      idempotency_key: "post-interest-paid-#{SecureRandom.hex(4)}",
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: @account.id,
      reference_id: accrued.id.to_s
    )[:event]
  end
end
