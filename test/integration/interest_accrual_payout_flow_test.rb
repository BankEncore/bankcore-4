# frozen_string_literal: true

require "test_helper"

class InterestAccrualPayoutFlowTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 22))
    party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Flow", last_name: "Interest")
    @account = Accounts::Commands::OpenAccount.call(party_record_id: party.id)
  end

  test "accrue then post increases DDA available balance only after payout" do
    opening_available = Accounts::Services::AvailableBalanceMinorUnits.call(deposit_account_id: @account.id)

    accrued = record_interest_accrued!(amount: 789)
    Core::Posting::Commands::PostEvent.call(operational_event_id: accrued.id)
    after_accrual_available = Accounts::Services::AvailableBalanceMinorUnits.call(deposit_account_id: @account.id)
    assert_equal opening_available, after_accrual_available

    payout = record_interest_posted!(accrued, amount: 789)
    Core::Posting::Commands::PostEvent.call(operational_event_id: payout.id)
    after_payout_available = Accounts::Services::AvailableBalanceMinorUnits.call(deposit_account_id: @account.id)
    assert_equal opening_available + 789, after_payout_available
  end

  private

  def record_interest_accrued!(amount:)
    Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "interest.accrued",
      channel: "system",
      idempotency_key: "flow-interest-accrued-#{SecureRandom.hex(4)}",
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: @account.id
    )[:event]
  end

  def record_interest_posted!(accrued, amount:)
    Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "interest.posted",
      channel: "system",
      idempotency_key: "flow-interest-posted-#{SecureRandom.hex(4)}",
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: @account.id,
      reference_id: accrued.id.to_s
    )[:event]
  end
end
