# frozen_string_literal: true

require "test_helper"

class AccountsDepositAccountNumberGeneratorTest < ActiveSupport::TestCase
  setup do
    Accounts::Models::DepositAccountNumberAllocation.delete_all
  end

  test "generates 12 digit account number with date, sequence, and Luhn check digit" do
    account_number = Accounts::Services::DepositAccountNumberGenerator.call(on_date: Date.new(2026, 4, 30))

    assert_equal "126040000013", account_number
    assert Accounts::Services::DepositAccountNumberGenerator.valid_luhn?(account_number)
  end

  test "increments the global sequence across months" do
    first = Accounts::Services::DepositAccountNumberGenerator.call(on_date: Date.new(2026, 4, 30))
    second = Accounts::Services::DepositAccountNumberGenerator.call(on_date: Date.new(2026, 5, 1))

    assert_equal "000001", first[5, 6]
    assert_equal "000002", second[5, 6]
    assert_equal "12605", second.first(5)
  end

  test "raises when global six digit sequence is exhausted" do
    Accounts::Models::DepositAccountNumberAllocation.create!(
      allocation_key: Accounts::Models::DepositAccountNumberAllocation::GLOBAL_KEY,
      last_sequence: Accounts::Models::DepositAccountNumberAllocation::MAX_SEQUENCE
    )

    assert_raises(Accounts::Services::DepositAccountNumberGenerator::SequenceExhausted) do
      Accounts::Services::DepositAccountNumberGenerator.call(on_date: Date.new(2026, 4, 30))
    end
  end

  test "valid_luhn rejects bad format and bad check digit" do
    assert_not Accounts::Services::DepositAccountNumberGenerator.valid_luhn?("DAABC123")
    assert_not Accounts::Services::DepositAccountNumberGenerator.valid_luhn?("126040000014")
  end
end
