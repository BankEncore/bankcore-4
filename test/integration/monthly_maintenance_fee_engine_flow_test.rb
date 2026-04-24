# frozen_string_literal: true

require "test_helper"

class MonthlyMaintenanceFeeEngineFlowTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 22))
    @product = Products::Models::DepositProduct.create!(
      product_code: "fee-flow-#{SecureRandom.hex(4)}",
      name: "Fee Flow",
      status: Products::Models::DepositProduct::STATUS_ACTIVE,
      currency: "USD"
    )
    @rule = Products::Models::DepositProductFeeRule.create!(
      deposit_product: @product,
      fee_code: Products::Models::DepositProductFeeRule::FEE_CODE_MONTHLY_MAINTENANCE,
      amount_minor_units: 350,
      currency: "USD",
      status: Products::Models::DepositProductFeeRule::STATUS_ACTIVE,
      effective_on: Date.new(2026, 4, 1)
    )
    @account = open_account!
    fund_account!(10_000)
  end

  test "monthly fee engine posts fee and reduces available balance" do
    before_available = Accounts::Services::AvailableBalanceMinorUnits.call(deposit_account_id: @account.id)

    result = Accounts::Commands::AssessMonthlyMaintenanceFees.call(
      business_date: Date.new(2026, 4, 22),
      deposit_product_id: @product.id
    )

    assert_equal 1, result.counts[:posted]
    after_available = Accounts::Services::AvailableBalanceMinorUnits.call(deposit_account_id: @account.id)
    assert_equal before_available - 350, after_available

    event = Core::OperationalEvents::Models::OperationalEvent.find(result.outcomes.sole.fetch(:operational_event_id))
    assert_equal "fee.assessed", event.event_type
    assert_equal "monthly_maintenance:#{@rule.id}:2026-04-22", event.reference_id
    assert_equal "posted", event.status
    assert_equal 1, event.journal_entries.count
  end

  private

  def open_account!
    party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Flow", last_name: "Fee")
    Accounts::Commands::OpenAccount.call(party_record_id: party.id, deposit_product_id: @product.id)
  end

  def fund_account!(amount)
    event = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "batch",
      idempotency_key: "fee-flow-fund-#{SecureRandom.hex(4)}",
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: @account.id
    )[:event]
    Core::Posting::Commands::PostEvent.call(operational_event_id: event.id)
  end
end
