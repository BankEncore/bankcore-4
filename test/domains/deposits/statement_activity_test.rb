# frozen_string_literal: true

require "test_helper"

class DepositsStatementActivityTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    set_business_date(Date.new(2026, 3, 31))
    @product = create_product!("statement-activity")
    @account = open_account!(@product)
    @destination = open_account!(@product)
  end

  test "derives customer-visible statement activity from 2110 and servicing events" do
    post_event!(record_event!("deposit.accepted", amount: 10_000, source_account_id: @account.id))

    set_business_date(Date.new(2026, 4, 2))
    withdrawal = post_event!(record_event!("withdrawal.posted", amount: 1_000, source_account_id: @account.id))

    set_business_date(Date.new(2026, 4, 3))
    post_event!(record_event!(
      "transfer.completed",
      amount: 2_000,
      source_account_id: @account.id,
      destination_account_id: @destination.id
    ))

    set_business_date(Date.new(2026, 4, 4))
    accrued = post_event!(record_event!("interest.accrued", amount: 50, source_account_id: @account.id, channel: "system"))
    post_event!(record_event!(
      "interest.posted",
      amount: 50,
      source_account_id: @account.id,
      channel: "system",
      reference_id: accrued.id.to_s
    ))

    set_business_date(Date.new(2026, 4, 5))
    Accounts::Commands::PlaceHold.call(
      deposit_account_id: @account.id,
      amount_minor_units: 500,
      currency: "USD",
      channel: "batch",
      idempotency_key: "stmt-hold-#{SecureRandom.hex(4)}"
    )

    set_business_date(Date.new(2026, 4, 6))
    Core::OperationalEvents::Commands::RecordControlEvent.call(
      event_type: "overdraft.nsf_denied",
      channel: "batch",
      idempotency_key: "stmt-nsf-#{SecureRandom.hex(4)}",
      reference_id: "attempt:withdrawal.posted",
      amount_minor_units: 12_000,
      currency: "USD",
      source_account_id: @account.id
    )

    set_business_date(Date.new(2026, 4, 7))
    reversal = Core::OperationalEvents::Commands::RecordReversal.call(
      original_operational_event_id: withdrawal.id,
      channel: "batch",
      idempotency_key: "stmt-reversal-#{SecureRandom.hex(4)}"
    )[:event]
    post_event!(reversal)

    set_business_date(Date.new(2026, 4, 8))
    fee = post_event!(record_event!("fee.assessed", amount: 300, source_account_id: @account.id))

    set_business_date(Date.new(2026, 4, 9))
    post_event!(record_event!("fee.waived", amount: 300, source_account_id: @account.id, reference_id: fee.id.to_s))

    result = Deposits::Queries::StatementActivity.call(
      deposit_account_id: @account.id,
      period_start_on: Date.new(2026, 4, 1),
      period_end_on: Date.new(2026, 4, 30)
    )

    assert_equal 10_000, result.opening_ledger_balance_minor_units
    assert_equal 8_050, result.closing_ledger_balance_minor_units
    assert_equal 3_300, result.total_debits_minor_units
    assert_equal 1_350, result.total_credits_minor_units

    event_types = result.line_items.map { |line| line.fetch(:event_type) }
    assert_includes event_types, "withdrawal.posted"
    assert_includes event_types, "transfer.completed"
    assert_includes event_types, "interest.posted"
    assert_includes event_types, "posting.reversal"
    assert_includes event_types, "fee.assessed"
    assert_includes event_types, "fee.waived"
    assert_includes event_types, "hold.placed"
    assert_includes event_types, "overdraft.nsf_denied"
    assert_not_includes event_types, "interest.accrued"

    servicing = result.line_items.select { |line| line.fetch(:line_type) == "servicing" }
    assert_equal [ false ], servicing.map { |line| line.fetch(:affects_ledger) }.uniq
    assert servicing.all? { |line| line.fetch(:running_ledger_balance_minor_units).nil? }
  end

  test "uses daily snapshots for closed-period opening and closing balances" do
    snapshot!(account: @account, as_of_date: Date.new(2026, 3, 31), ledger: 1_000)

    set_business_date(Date.new(2026, 4, 15))
    post_event!(record_event!("deposit.accepted", amount: 5_000, source_account_id: @account.id))
    snapshot!(account: @account, as_of_date: Date.new(2026, 4, 30), ledger: 6_000)

    result = Deposits::Queries::StatementActivity.call(
      deposit_account_id: @account.id,
      period_start_on: Date.new(2026, 4, 1),
      period_end_on: Date.new(2026, 4, 30)
    )

    assert_equal 1_000, result.opening_ledger_balance_minor_units
    assert_equal 6_000, result.closing_ledger_balance_minor_units
    assert_equal 5_000, result.total_credits_minor_units
    assert_equal 6_000, result.line_items.sole.fetch(:running_ledger_balance_minor_units)
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

  def open_account!(product)
    party = Party::Commands::CreateParty.call(
      party_type: "individual",
      first_name: "Statement",
      last_name: SecureRandom.hex(3)
    )
    Accounts::Commands::OpenAccount.call(party_record_id: party.id, deposit_product_id: product.id)
  end

  def record_event!(event_type, amount:, source_account_id:, channel: "batch", destination_account_id: nil, reference_id: nil)
    Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: event_type,
      channel: channel,
      idempotency_key: "stmt-#{event_type}-#{SecureRandom.hex(4)}",
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: source_account_id,
      destination_account_id: destination_account_id,
      reference_id: reference_id
    )[:event]
  end

  def post_event!(event)
    Core::Posting::Commands::PostEvent.call(operational_event_id: event.id)
    event.reload
  end

  def snapshot!(account:, as_of_date:, ledger:)
    Reporting::Models::DailyBalanceSnapshot.create!(
      account_domain: Reporting::Models::DailyBalanceSnapshot::ACCOUNT_DOMAIN_DEPOSITS,
      account_id: account.id,
      account_type: Reporting::Models::DailyBalanceSnapshot::ACCOUNT_TYPE_DEPOSIT_ACCOUNT,
      as_of_date: as_of_date,
      ledger_balance_minor_units: ledger,
      hold_balance_minor_units: 0,
      available_balance_minor_units: ledger,
      source: Reporting::Models::DailyBalanceSnapshot::SOURCE_CURRENT_PROJECTION,
      calculation_version: Accounts::Models::DepositAccountBalanceProjection::CURRENT_CALCULATION_VERSION
    )
  end
end
