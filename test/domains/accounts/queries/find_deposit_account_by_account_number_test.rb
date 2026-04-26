# frozen_string_literal: true

require "test_helper"

class AccountsQueriesFindDepositAccountByAccountNumberTest < ActiveSupport::TestCase
  setup do
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 25))
    party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Ach", last_name: "Lookup")
    @account = Accounts::Commands::OpenAccount.call(party_record_id: party.id)
    @account.update!(account_number: "001234567890")
  end

  test "finds an account by exact normalized account number preserving leading zeroes" do
    found = Accounts::Queries::FindDepositAccountByAccountNumber.call(account_number: " 001234567890 ")

    assert_equal @account.id, found.id
  end

  test "open returns nil for closed account" do
    @account.update!(status: Accounts::Models::DepositAccount::STATUS_CLOSED)

    assert_nil Accounts::Queries::FindDepositAccountByAccountNumber.open(account_number: "001234567890")
  end

  test "blank account number is invalid" do
    assert_raises(Accounts::Queries::FindDepositAccountByAccountNumber::InvalidAccountNumber) do
      Accounts::Queries::FindDepositAccountByAccountNumber.call(account_number: " ")
    end
  end
end
