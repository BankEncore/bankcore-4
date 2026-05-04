# frozen_string_literal: true

require "test_helper"

class GlCoaSeedTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
  end

  test "chart of accounts seeds from TSV with expected slice accounts" do
    assert_operator BankCore::Seeds::GlCoa.rows_from_tsv.size, :>=, 80

    vault_cash = Core::Ledger::Models::GlAccount.find_by!(account_number: "1110")
    dda = Core::Ledger::Models::GlAccount.find_by!(account_number: "2110")
    clearing = Core::Ledger::Models::GlAccount.find_by!(account_number: "1160")

    assert_equal "asset", clearing.account_type
    assert_equal "debit", clearing.natural_balance
    assert_includes clearing.account_name, "Deposited Items"

    assert_equal "asset", vault_cash.account_type
    assert_equal "debit", vault_cash.natural_balance
    assert_includes vault_cash.account_name, "Vault"
    assert_equal "liability", dda.account_type
    assert_equal "credit", dda.natural_balance
    assert_includes dda.account_name, "Demand"
  end
end
