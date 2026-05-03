# frozen_string_literal: true

require "test_helper"

class AccountsDepositAccountBalanceProjectionTest < ActiveSupport::TestCase
  setup do
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 5, 2))
    party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Balance", last_name: "Projection")
    @account = Accounts::Commands::OpenAccount.call(party_record_id: party.id)
  end

  test "stores one projection per deposit account with default zero balances" do
    projection = Accounts::Models::DepositAccountBalanceProjection.create!(deposit_account: @account)

    assert_equal 0, projection.ledger_balance_minor_units
    assert_equal 0, projection.hold_balance_minor_units
    assert_equal 0, projection.available_balance_minor_units
    assert_equal 1, projection.calculation_version
    assert_not projection.stale
    assert_equal projection, @account.reload.deposit_account_balance_projection
  end

  test "allows negative ledger and available balances but not negative hold totals" do
    projection = Accounts::Models::DepositAccountBalanceProjection.new(
      deposit_account: @account,
      ledger_balance_minor_units: -1_00,
      hold_balance_minor_units: -1,
      available_balance_minor_units: -1_00
    )

    assert_not projection.valid?
    assert_includes projection.errors[:hold_balance_minor_units], "must be greater than or equal to 0"

    projection.hold_balance_minor_units = 0
    assert projection.valid?
  end

  test "requires a positive calculation version" do
    projection = Accounts::Models::DepositAccountBalanceProjection.new(
      deposit_account: @account,
      calculation_version: 0
    )

    assert_not projection.valid?
    assert_includes projection.errors[:calculation_version], "must be greater than 0"
  end

  test "enforces uniqueness by deposit account" do
    Accounts::Models::DepositAccountBalanceProjection.create!(deposit_account: @account)

    duplicate = Accounts::Models::DepositAccountBalanceProjection.new(deposit_account: @account)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:deposit_account], "has already been taken"
  end
end
