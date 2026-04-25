# frozen_string_literal: true

require "test_helper"

class DepositAccountProfileTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 9, 2))
    @product = Products::Queries::FindDepositProduct.default_slice1!
    @operator = Workspace::Models::Operator.create!(role: "teller", display_name: "Profile Teller", active: true)
  end

  test "returns account, ownership, product, and balance summary" do
    party = create_party!("Profile", "Owner")
    account = Accounts::Commands::OpenAccount.call(party_record_id: party.id, deposit_product_id: @product.id)
    fund_account!(account, amount: 10_000)
    Accounts::Commands::PlaceHold.call(
      deposit_account_id: account.id,
      amount_minor_units: 1_500,
      currency: "USD",
      channel: "branch",
      idempotency_key: "profile-hold",
      actor_id: @operator.id
    )

    result = Accounts::Queries::DepositAccountProfile.call(deposit_account_id: account.id)

    assert_equal account.id, result.account.id
    assert_equal @product.id, result.product.id
    assert_equal 1, result.owners.size
    assert_equal 10_000, result.ledger_balance_minor_units
    assert_equal 8_500, result.available_balance_minor_units
    assert_equal 1_500, result.active_hold_total_minor_units
    assert_equal Date.new(2026, 9, 2), result.current_business_date
  end

  private

  def create_party!(first_name, last_name)
    Party::Commands::CreateParty.call(party_type: "individual", first_name: first_name, last_name: last_name)
  end

  def fund_account!(account, amount:)
    event = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "branch",
      idempotency_key: "profile-funding",
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: account.id,
      actor_id: @operator.id
    )[:event]
    Core::Posting::Commands::PostEvent.call(operational_event_id: event.id)
  end
end
