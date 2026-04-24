# frozen_string_literal: true

require "test_helper"

class DepositsStatementCycleServiceTest < ActiveSupport::TestCase
  setup do
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 24))
    @product = Products::Models::DepositProduct.create!(
      product_code: "statement-cycle-#{SecureRandom.hex(4)}",
      name: "Statement Cycle Product",
      status: Products::Models::DepositProduct::STATUS_ACTIVE,
      currency: "USD"
    )
    @profile = Products::Models::DepositProductStatementProfile.create!(
      deposit_product: @product,
      frequency: Products::Models::DepositProductStatementProfile::FREQUENCY_MONTHLY,
      cycle_day: 31,
      currency: "USD",
      status: Products::Models::DepositProductStatementProfile::STATUS_ACTIVE,
      effective_on: Date.new(2026, 4, 1)
    )
    @account = open_account!(@product)
    timestamp = Time.zone.local(2026, 4, 30, 12, 0, 0)
    @account.update_columns(created_at: timestamp, updated_at: timestamp)
  end

  test "clamps cycle day to month end" do
    period = Deposits::Services::StatementCycleService.period_for(date: Date.new(2026, 2, 28), cycle_day: 31)

    assert_equal Date.new(2026, 2, 28), period.period_start_on
    assert_equal Date.new(2026, 3, 30), period.period_end_on
  end

  test "due periods return completed periods before generated date" do
    periods = Deposits::Services::StatementCycleService.due_periods(
      profile: @profile,
      account: @account,
      generated_on: Date.new(2026, 5, 31)
    )

    assert_equal Date.new(2026, 4, 30), periods.first.period_start_on
    assert_equal Date.new(2026, 5, 30), periods.first.period_end_on
  end

  test "uses last statement to continue with the next period" do
    last_statement = Deposits::Models::DepositStatement.create!(
      deposit_account: @account,
      deposit_product_statement_profile: @profile,
      period_start_on: Date.new(2026, 4, 30),
      period_end_on: Date.new(2026, 5, 30),
      currency: "USD",
      opening_ledger_balance_minor_units: 0,
      closing_ledger_balance_minor_units: 0,
      total_debits_minor_units: 0,
      total_credits_minor_units: 0,
      line_items: [],
      status: Deposits::Models::DepositStatement::STATUS_GENERATED,
      generated_on: Date.new(2026, 5, 31),
      generated_at: Time.current,
      idempotency_key: "stmt-cycle-last-#{SecureRandom.hex(4)}"
    )

    periods = Deposits::Services::StatementCycleService.due_periods(
      profile: @profile,
      account: @account,
      generated_on: Date.new(2026, 7, 1),
      last_statement: last_statement
    )

    assert_equal Date.new(2026, 5, 31), periods.first.period_start_on
    assert_equal Date.new(2026, 6, 29), periods.first.period_end_on
  end

  private

  def open_account!(product)
    party = Party::Commands::CreateParty.call(
      party_type: "individual",
      first_name: "Statement",
      last_name: SecureRandom.hex(3)
    )
    Accounts::Commands::OpenAccount.call(party_record_id: party.id, deposit_product_id: product.id)
  end
end
