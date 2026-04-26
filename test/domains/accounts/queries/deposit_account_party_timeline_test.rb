# frozen_string_literal: true

require "test_helper"

class DepositAccountPartyTimelineTest < ActiveSupport::TestCase
  setup do
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 9, 4))
    @product = Products::Queries::FindDepositProduct.default_slice1!
  end

  test "partitions party relationships into current and historical rows" do
    party = create_party!("Timeline", "Party")
    current_account = Accounts::Commands::OpenAccount.call(party_record_id: party.id, deposit_product_id: @product.id)
    old_account = Accounts::Commands::OpenAccount.call(party_record_id: party.id, deposit_product_id: @product.id)
    old_relationship = old_account.deposit_account_parties.find_by!(party_record_id: party.id)
    old_relationship.update!(
      status: Accounts::Models::DepositAccountParty::STATUS_INACTIVE,
      ended_on: Date.new(2026, 8, 31)
    )

    result = Accounts::Queries::DepositAccountPartyTimeline.call(party_record_id: party.id, as_of: Date.new(2026, 9, 4))

    assert_equal party.id, result.party.id
    assert_equal [ current_account.id ], result.current_rows.map { |row| row.account.id }
    assert_equal [ old_account.id ], result.historical_rows.map { |row| row.account.id }
    assert_equal @product.id, result.current_rows.first.product.id
  end

  test "partitions account parties into current and historical rows" do
    owner = create_party!("Current", "Owner")
    historical_owner = create_party!("Former", "Owner")
    account = Accounts::Commands::OpenAccount.call(party_record_id: owner.id, deposit_product_id: @product.id)
    Accounts::Models::DepositAccountParty.create!(
      deposit_account: account,
      party_record: historical_owner,
      role: Accounts::Models::DepositAccountParty::ROLE_JOINT_OWNER,
      status: Accounts::Models::DepositAccountParty::STATUS_INACTIVE,
      effective_on: Date.new(2026, 8, 1),
      ended_on: Date.new(2026, 8, 31)
    )

    result = Accounts::Queries::DepositAccountPartyTimeline.call(deposit_account_id: account.id, as_of: Date.new(2026, 9, 4))

    assert_equal account.id, result.account.id
    assert_equal [ owner.id ], result.current_rows.map { |row| row.party.id }
    assert_equal [ historical_owner.id ], result.historical_rows.map { |row| row.party.id }
  end

  private

  def create_party!(first_name, last_name)
    Party::Commands::CreateParty.call(party_type: "individual", first_name: first_name, last_name: last_name)
  end
end
