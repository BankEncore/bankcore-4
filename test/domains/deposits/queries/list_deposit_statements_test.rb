# frozen_string_literal: true

require "test_helper"

class ListDepositStatementsTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 9, 4))
    @product = Products::Queries::FindDepositProduct.default_slice1!
  end

  test "lists generated statement metadata with pagination" do
    account = open_account!
    profile = Products::Queries::ActiveStatementProfiles.monthly(
      business_date: Date.new(2026, 9, 4),
      deposit_product_id: @product.id
    ).last

    older = create_statement!(account, profile, start_on: Date.new(2026, 7, 1), key: "stmt-old")
    newer = create_statement!(account, profile, start_on: Date.new(2026, 8, 1), key: "stmt-new")

    result = Deposits::Queries::ListDepositStatements.call(deposit_account_id: account.id, limit: 1)

    assert_equal account.id, result.account.id
    assert_equal [ newer.id ], result.rows.map(&:id)
    assert result.has_more
    assert_equal newer.id, result.next_after_id

    next_page = Deposits::Queries::ListDepositStatements.call(deposit_account_id: account.id, limit: 1, after_id: result.next_after_id)
    assert_equal [ older.id ], next_page.rows.map(&:id)
  end

  private

  def open_account!
    party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Statement", last_name: SecureRandom.hex(3))
    Accounts::Commands::OpenAccount.call(party_record_id: party.id, deposit_product_id: @product.id)
  end

  def create_statement!(account, profile, start_on:, key:)
    Deposits::Models::DepositStatement.create!(
      deposit_account: account,
      deposit_product_statement_profile: profile,
      period_start_on: start_on,
      period_end_on: start_on.end_of_month,
      currency: account.currency,
      opening_ledger_balance_minor_units: 0,
      closing_ledger_balance_minor_units: 0,
      total_debits_minor_units: 0,
      total_credits_minor_units: 0,
      line_items: [],
      status: Deposits::Models::DepositStatement::STATUS_GENERATED,
      generated_on: Date.new(2026, 9, 4),
      generated_at: Time.current,
      idempotency_key: key
    )
  end
end
