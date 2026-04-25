# frozen_string_literal: true

require "test_helper"

class DepositAccountsForPartyTest < ActiveSupport::TestCase
  setup do
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 9, 1))
    @product = Products::Queries::FindDepositProduct.default_slice1!
  end

  test "lists active deposit account relationships for party" do
    party = create_party!("Query", "Owner")
    account = Accounts::Commands::OpenAccount.call(party_record_id: party.id, deposit_product_id: @product.id)

    result = Accounts::Queries::DepositAccountsForParty.call(party_record_id: party.id)

    assert_equal party.id, result.party.id
    assert_equal [ account.id ], result.rows.map { |row| row.account.id }
    assert_equal @product.id, result.rows.first.product.id
    assert_equal Accounts::Models::DepositAccountParty::ROLE_OWNER, result.rows.first.relationship.role
  end

  private

  def create_party!(first_name, last_name)
    Party::Commands::CreateParty.call(party_type: "individual", first_name: first_name, last_name: last_name)
  end
end
