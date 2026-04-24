# frozen_string_literal: true

require "test_helper"

class AccountsAssessMonthlyMaintenanceFeesTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 22))
    @product = create_product!("monthly-fee")
    @rule = create_rule!(@product, amount_minor_units: 500)
  end

  test "creates and posts monthly maintenance fee for eligible account" do
    account = open_account!(@product)
    fund_account!(account, 10_000)

    result = Accounts::Commands::AssessMonthlyMaintenanceFees.call(
      business_date: Date.new(2026, 4, 22),
      deposit_product_id: @product.id
    )

    assert_equal 1, result.counts[:posted]
    event = Core::OperationalEvents::Models::OperationalEvent.find(result.outcomes.sole.fetch(:operational_event_id))
    assert_equal "fee.assessed", event.event_type
    assert_equal "system", event.channel
    assert_equal "monthly_maintenance:#{@rule.id}:2026-04-22", event.reference_id
    assert_equal "posted", event.status
    assert_equal account.id, event.source_account_id
    assert_equal 500, event.amount_minor_units

    lines = event.posting_batches.sole.journal_entries.sole.journal_lines.order(:sequence_no)
    assert_equal "2110", lines.first.gl_account.account_number
    assert_equal "4510", lines.second.gl_account.account_number
  end

  test "rerun is idempotent and does not double charge" do
    account = open_account!(@product)
    fund_account!(account, 10_000)

    first = Accounts::Commands::AssessMonthlyMaintenanceFees.call(
      business_date: Date.new(2026, 4, 22),
      deposit_product_id: @product.id
    )
    second = Accounts::Commands::AssessMonthlyMaintenanceFees.call(
      business_date: Date.new(2026, 4, 22),
      deposit_product_id: @product.id
    )

    assert_equal 1, first.counts[:posted]
    assert_equal 1, second.counts[:already_posted]
    assert_equal 1, Core::OperationalEvents::Models::OperationalEvent.where(
      event_type: "fee.assessed",
      source_account_id: account.id,
      reference_id: "monthly_maintenance:#{@rule.id}:2026-04-22"
    ).count
  end

  test "skips insufficient available balance" do
    account = open_account!(@product)

    result = Accounts::Commands::AssessMonthlyMaintenanceFees.call(
      business_date: Date.new(2026, 4, 22),
      deposit_product_id: @product.id
    )

    assert_equal 1, result.counts[:skipped_insufficient_available_balance]
    assert_equal account.id, result.outcomes.sole.fetch(:deposit_account_id)
    assert_nil result.outcomes.sole[:operational_event_id]
  end

  test "ignores closed accounts" do
    account = open_account!(@product)
    fund_account!(account, 10_000)
    account.update!(status: Accounts::Models::DepositAccount::STATUS_CLOSED)

    result = Accounts::Commands::AssessMonthlyMaintenanceFees.call(
      business_date: Date.new(2026, 4, 22),
      deposit_product_id: @product.id
    )

    assert_empty result.outcomes
  end

  test "product filter limits assessment scope" do
    other_product = create_product!("other-monthly-fee")
    create_rule!(other_product, amount_minor_units: 700)
    account = open_account!(@product)
    other_account = open_account!(other_product)
    fund_account!(account, 10_000)
    fund_account!(other_account, 10_000)

    result = Accounts::Commands::AssessMonthlyMaintenanceFees.call(
      business_date: Date.new(2026, 4, 22),
      deposit_product_id: @product.id
    )

    assert_equal 1, result.counts[:posted]
    assert_equal account.id, result.outcomes.sole.fetch(:deposit_account_id)
  end

  test "account_ids limits assessment scope" do
    account = open_account!(@product)
    other_account = open_account!(@product)
    fund_account!(account, 10_000)
    fund_account!(other_account, 10_000)

    result = Accounts::Commands::AssessMonthlyMaintenanceFees.call(
      business_date: Date.new(2026, 4, 22),
      deposit_product_id: @product.id,
      account_ids: [ account.id ]
    )

    assert_equal 1, result.counts[:posted]
    assert_equal account.id, result.outcomes.sole.fetch(:deposit_account_id)
  end

  test "rejects non-system channel" do
    assert_raises(Accounts::Commands::AssessMonthlyMaintenanceFees::InvalidRequest) do
      Accounts::Commands::AssessMonthlyMaintenanceFees.call(channel: "batch")
    end
  end

  private

  def create_product!(prefix)
    Products::Models::DepositProduct.create!(
      product_code: "#{prefix}-#{SecureRandom.hex(4)}",
      name: prefix,
      status: Products::Models::DepositProduct::STATUS_ACTIVE,
      currency: "USD"
    )
  end

  def create_rule!(product, attrs = {})
    Products::Models::DepositProductFeeRule.create!({
      deposit_product: product,
      fee_code: Products::Models::DepositProductFeeRule::FEE_CODE_MONTHLY_MAINTENANCE,
      amount_minor_units: 500,
      currency: "USD",
      status: Products::Models::DepositProductFeeRule::STATUS_ACTIVE,
      effective_on: Date.new(2026, 4, 1)
    }.merge(attrs))
  end

  def open_account!(product)
    party = Party::Commands::CreateParty.call(
      party_type: "individual",
      first_name: "Fee",
      last_name: SecureRandom.hex(3)
    )
    Accounts::Commands::OpenAccount.call(party_record_id: party.id, deposit_product_id: product.id)
  end

  def fund_account!(account, amount)
    event = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "batch",
      idempotency_key: "fund-monthly-fee-#{SecureRandom.hex(4)}",
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: account.id
    )[:event]
    Core::Posting::Commands::PostEvent.call(operational_event_id: event.id)
  end
end
