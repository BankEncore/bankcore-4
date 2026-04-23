# frozen_string_literal: true

require "test_helper"

class TrialBalanceQueriesTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    @bd = Date.new(2026, 4, 22)
    Core::BusinessDate::Commands::SetBusinessDate.call(on: @bd)
    party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "T", last_name: "B")
    @account = Accounts::Commands::OpenAccount.call(party_record_id: party.id)
  end

  test "trial balance and journal totals after post" do
    ev = record_deposit!(12_34)
    Core::Posting::Commands::PostEvent.call(operational_event_id: ev.id)

    chk = Core::Ledger::Queries::JournalBalanceCheckForBusinessDate.call(business_date: @bd)
    assert_predicate chk, :balanced
    assert_equal 12_34, chk.total_debit_minor_units
    assert_equal 12_34, chk.total_credit_minor_units

    rows = Core::Ledger::Queries::TrialBalanceForBusinessDate.call(business_date: @bd)
    assert_equal 2, rows.size
    cash = rows.find { |r| r.account_number == "1110" }
    liab = rows.find { |r| r.account_number == "2110" }
    assert_equal 12_34, cash.debit_minor_units
    assert_equal 0, cash.credit_minor_units
    assert_equal 0, liab.debit_minor_units
    assert_equal 12_34, liab.credit_minor_units
  end

  test "empty date yields empty trial balance and zero balanced totals" do
    chk = Core::Ledger::Queries::JournalBalanceCheckForBusinessDate.call(business_date: Date.new(2020, 1, 1))
    assert_predicate chk, :balanced
    assert_equal 0, chk.total_debit_minor_units
    assert_equal 0, chk.total_credit_minor_units

    rows = Core::Ledger::Queries::TrialBalanceForBusinessDate.call(business_date: Date.new(2020, 1, 1))
    assert_empty rows
  end

  test "rejects non-Date" do
    assert_raises(ArgumentError) do
      Core::Ledger::Queries::TrialBalanceForBusinessDate.call(business_date: "2026-04-22")
    end
    assert_raises(ArgumentError) do
      Core::Ledger::Queries::JournalBalanceCheckForBusinessDate.call(business_date: "2026-04-22")
    end
  end

  private

  def record_deposit!(amount)
    Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "batch",
      idempotency_key: "tb-test-#{SecureRandom.hex(6)}",
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: @account.id
    )[:event]
  end
end
