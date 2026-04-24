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
    assert_equal account.deposit_product_id, account.deposit_product.id
    assert_equal Accounts::SLICE1_PRODUCT_CODE, account.deposit_product.product_code
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

  test "raises when product_code is unknown" do
    assert_raises(Accounts::Commands::OpenAccount::ProductNotFound) do
      Accounts::Commands::OpenAccount.call(party_record_id: @party.id, product_code: "no_such_product")
    end
  end

  test "raises when deposit_product_id and product_code disagree" do
    other = Products::Models::DepositProduct.create!(
      product_code: "other_test_product",
      name: "Other",
      status: Products::Models::DepositProduct::STATUS_ACTIVE,
      currency: "USD"
    )
    assert_raises(Accounts::Commands::OpenAccount::ProductConflict) do
      Accounts::Commands::OpenAccount.call(
        party_record_id: @party.id,
        deposit_product_id: other.id,
        product_code: Accounts::SLICE1_PRODUCT_CODE
      )
    end
  end

  test "opens account by deposit_product_id" do
    prod = Products::Models::DepositProduct.find_by!(product_code: Accounts::SLICE1_PRODUCT_CODE)
    account = Accounts::Commands::OpenAccount.call(party_record_id: @party.id, deposit_product_id: prod.id)
    assert_equal prod.id, account.deposit_product_id
  end

  test "CreateParty then OpenAccount" do
    party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "X", last_name: "Y")
    account = Accounts::Commands::OpenAccount.call(party_record_id: party.id)
    assert_equal party.id, account.deposit_account_parties.first.party_record_id
  end

  test "opens joint account with owner and joint_owner participations" do
    joint = Party::Commands::CreateParty.call(party_type: "individual", first_name: "J", last_name: "Co")
    account = Accounts::Commands::OpenAccount.call(party_record_id: @party.id, joint_party_record_id: joint.id)
    assert_equal 2, account.deposit_account_parties.count
    owner_row = account.deposit_account_parties.find_by!(party_record_id: @party.id)
    joint_row = account.deposit_account_parties.find_by!(party_record_id: joint.id)
    assert_equal Accounts::Models::DepositAccountParty::ROLE_OWNER, owner_row.role
    assert_equal Accounts::Models::DepositAccountParty::ROLE_JOINT_OWNER, joint_row.role
    assert_equal owner_row.effective_on, joint_row.effective_on
    assert_nil joint_row.ended_on
  end

  test "raises InvalidJointParty when joint_party_record_id equals party_record_id" do
    assert_raises(Accounts::Commands::OpenAccount::InvalidJointParty) do
      Accounts::Commands::OpenAccount.call(party_record_id: @party.id, joint_party_record_id: @party.id)
    end
  end

  test "raises JointPartyNotFound when joint party is missing" do
    assert_raises(Accounts::Commands::OpenAccount::JointPartyNotFound) do
      Accounts::Commands::OpenAccount.call(party_record_id: @party.id, joint_party_record_id: 9_999_998)
    end
  end
end
