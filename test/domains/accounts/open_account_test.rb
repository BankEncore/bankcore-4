# frozen_string_literal: true

require "test_helper"

class AccountsOpenAccountTest < ActiveSupport::TestCase
  setup do
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 21))
    @party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "A", last_name: "B")
  end

  test "opens account with owner participation and slice product code" do
    account = Accounts::Commands::OpenAccount.call(party_record_id: @party.id)
    assert account.persisted?
    assert_equal Accounts::SLICE1_PRODUCT_CODE, account.product_code
    assert_equal Accounts::Models::DepositAccount::STATUS_OPEN, account.status
    assert_equal "USD", account.currency
    assert_equal 1, account.deposit_account_parties.count
    row = account.deposit_account_parties.first
    assert_equal Accounts::Models::DepositAccountParty::ROLE_OWNER, row.role
    assert_equal Accounts::Models::DepositAccountParty::STATUS_ACTIVE, row.status
    assert_equal Date.new(2026, 4, 21), row.effective_on
    assert_nil row.ended_on
  end

  test "uses explicit effective_on when provided" do
    on = Date.new(2026, 5, 1)
    account = Accounts::Commands::OpenAccount.call(party_record_id: @party.id, effective_on: on)
    assert_equal on, account.deposit_account_parties.first.effective_on
  end

  test "raises when party is missing" do
    assert_raises(Accounts::Commands::OpenAccount::PartyNotFound) do
      Accounts::Commands::OpenAccount.call(party_record_id: 9_999_999)
    end
  end

  test "CreateParty then OpenAccount" do
    party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "X", last_name: "Y")
    account = Accounts::Commands::OpenAccount.call(party_record_id: party.id)
    assert_equal party.id, account.deposit_account_parties.first.party_record_id
  end
end
