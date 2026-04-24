# frozen_string_literal: true

require "test_helper"

class DepositsGenerateDepositStatementsTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    set_business_date(Date.new(2026, 4, 15))
    @product = create_product!("statement-generate")
    @profile = create_profile!(@product)
    @account = open_account!(@product, opened_on: Date.new(2026, 4, 15))
  end

  test "generates statement snapshot for completed product cycle" do
    fund_account!(@account, 5_000)

    result = Deposits::Commands::GenerateDepositStatements.call(
      business_date: Date.new(2026, 5, 1),
      deposit_product_id: @product.id
    )

    assert_equal 1, result.counts[:generated]
    statement = Deposits::Models::DepositStatement.find(result.outcomes.sole.fetch(:deposit_statement_id))
    assert_equal @account.id, statement.deposit_account_id
    assert_equal @profile.id, statement.deposit_product_statement_profile_id
    assert_equal Date.new(2026, 4, 1), statement.period_start_on
    assert_equal Date.new(2026, 4, 30), statement.period_end_on
    assert_equal 0, statement.opening_ledger_balance_minor_units
    assert_equal 5_000, statement.closing_ledger_balance_minor_units
    assert_equal 5_000, statement.total_credits_minor_units
    assert_equal [ "deposit.accepted" ], statement.line_items.map { |line| line.fetch("event_type") }
  end

  test "rerun is idempotent and reports already generated" do
    fund_account!(@account, 5_000)

    first = Deposits::Commands::GenerateDepositStatements.call(
      business_date: Date.new(2026, 5, 1),
      deposit_product_id: @product.id
    )
    second = Deposits::Commands::GenerateDepositStatements.call(
      business_date: Date.new(2026, 5, 1),
      deposit_product_id: @product.id
    )

    assert_equal 1, first.counts[:generated]
    assert_equal 1, second.counts[:already_generated]
    assert_equal 1, Deposits::Models::DepositStatement.where(deposit_account_id: @account.id).count
  end

  test "returns not due before first cycle completes" do
    result = Deposits::Commands::GenerateDepositStatements.call(
      business_date: Date.new(2026, 4, 20),
      deposit_product_id: @product.id
    )

    assert_equal 1, result.counts[:not_due]
    assert_empty Deposits::Models::DepositStatement.where(deposit_account_id: @account.id)
  end

  test "account_ids limits statement generation scope" do
    other = open_account!(@product, opened_on: Date.new(2026, 4, 15))
    fund_account!(@account, 5_000)
    fund_account!(other, 7_000)

    result = Deposits::Commands::GenerateDepositStatements.call(
      business_date: Date.new(2026, 5, 1),
      deposit_product_id: @product.id,
      account_ids: [ @account.id ]
    )

    assert_equal 1, result.counts[:generated]
    assert_equal @account.id, result.outcomes.sole.fetch(:deposit_account_id)
    assert_nil Deposits::Models::DepositStatement.find_by(deposit_account_id: other.id)
  end

  private

  def set_business_date(date)
    Core::BusinessDate::Commands::SetBusinessDate.call(on: date)
  end

  def create_product!(prefix)
    Products::Models::DepositProduct.create!(
      product_code: "#{prefix}-#{SecureRandom.hex(4)}",
      name: prefix,
      status: Products::Models::DepositProduct::STATUS_ACTIVE,
      currency: "USD"
    )
  end

  def create_profile!(product)
    Products::Models::DepositProductStatementProfile.create!(
      deposit_product: product,
      frequency: Products::Models::DepositProductStatementProfile::FREQUENCY_MONTHLY,
      cycle_day: 1,
      currency: "USD",
      status: Products::Models::DepositProductStatementProfile::STATUS_ACTIVE,
      effective_on: Date.new(2026, 4, 1)
    )
  end

  def open_account!(product, opened_on:)
    party = Party::Commands::CreateParty.call(
      party_type: "individual",
      first_name: "Statement",
      last_name: SecureRandom.hex(3)
    )
    account = Accounts::Commands::OpenAccount.call(party_record_id: party.id, deposit_product_id: product.id)
    timestamp = Time.zone.local(opened_on.year, opened_on.month, opened_on.day, 12, 0, 0)
    account.update_columns(created_at: timestamp, updated_at: timestamp)
    account
  end

  def fund_account!(account, amount)
    set_business_date(Date.new(2026, 4, 15))
    event = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "batch",
      idempotency_key: "fund-statement-#{SecureRandom.hex(4)}",
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: account.id
    )[:event]
    Core::Posting::Commands::PostEvent.call(operational_event_id: event.id)
    event.reload
  end
end
