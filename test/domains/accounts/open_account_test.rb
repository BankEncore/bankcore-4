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
    assert_match(/\A1\d{11}\z/, account.account_number)
    assert Accounts::Services::DepositAccountNumberGenerator.valid_luhn?(account.account_number)
    assert_equal "12604", account.account_number.first(5)
    assert_equal 1, account.deposit_account_parties.count
    row = account.deposit_account_parties.first
    assert_equal Accounts::Models::DepositAccountParty::ROLE_OWNER, row.role
    assert_equal Accounts::Models::DepositAccountParty::STATUS_ACTIVE, row.status
    assert_equal Date.new(2026, 4, 21), row.effective_on
    assert_nil row.ended_on
    projection = account.deposit_account_balance_projection
    assert_equal 0, projection.ledger_balance_minor_units
    assert_equal 0, projection.hold_balance_minor_units
    assert_equal 0, projection.available_balance_minor_units
    assert_equal Date.new(2026, 4, 21), projection.as_of_business_date
    assert_equal Accounts::Models::DepositAccountBalanceProjection::CURRENT_CALCULATION_VERSION, projection.calculation_version
  end

  test "uses explicit effective_on when provided" do
    on = Date.new(2026, 5, 1)
    account = Accounts::Commands::OpenAccount.call(party_record_id: @party.id, effective_on: on)
    assert_equal on, account.deposit_account_parties.first.effective_on
    assert_equal "12605", account.account_number.first(5)
  end

  test "allocates globally incrementing account numbers" do
    first = Accounts::Commands::OpenAccount.call(party_record_id: @party.id)
    second_party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Seq", last_name: "Two")
    second = Accounts::Commands::OpenAccount.call(party_record_id: second_party.id)

    assert_equal "000001", first.account_number[5, 6]
    assert_equal "000002", second.account_number[5, 6]
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

  test "deposit account validates numeric account number shape and check digit" do
    product = Products::Models::DepositProduct.find_by!(product_code: Accounts::SLICE1_PRODUCT_CODE)
    account = Accounts::Models::DepositAccount.new(
      account_number: "DAABC123",
      currency: "USD",
      status: Accounts::Models::DepositAccount::STATUS_OPEN,
      deposit_product: product,
      product_code: product.product_code
    )

    assert_not account.valid?
    assert_includes account.errors[:account_number], "must be a 12-digit deposit account number"

    account.account_number = "126040000014"
    assert_not account.valid?
    assert_includes account.errors[:account_number], "has an invalid check digit"
  end
end
