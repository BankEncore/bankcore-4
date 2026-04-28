# frozen_string_literal: true

require "test_helper"

class ListHoldsForAccountTest < ActiveSupport::TestCase
  setup do
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 9, 3))
    @operator = Workspace::Models::Operator.create!(role: "teller", display_name: "Hold Teller", active: true)
    @supervisor = Workspace::Models::Operator.create!(role: "supervisor", display_name: "Hold Supervisor", active: true)
  end

  test "lists holds and active total for an account" do
    account = open_account!
    active = Accounts::Commands::PlaceHold.call(
      deposit_account_id: account.id,
      amount_minor_units: 700,
      currency: "USD",
      channel: "branch",
      idempotency_key: "active-hold",
      actor_id: @operator.id
    )[:hold]
    released = Accounts::Commands::PlaceHold.call(
      deposit_account_id: account.id,
      amount_minor_units: 300,
      currency: "USD",
      channel: "branch",
      idempotency_key: "released-hold",
      actor_id: @operator.id
    )[:hold]
    Accounts::Commands::ReleaseHold.call(
      hold_id: released.id,
      channel: "branch",
      idempotency_key: "release-hold",
      actor_id: @supervisor.id
    )

    result = Accounts::Queries::ListHoldsForAccount.call(deposit_account_id: account.id)

    assert_equal account.id, result.account.id
    assert_equal 700, result.active_total_minor_units
    assert_includes result.holds.map(&:id), active.id
    assert_includes result.holds.map(&:id), released.id
  end

  private

  def open_account!
    party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Hold", last_name: SecureRandom.hex(3))
    Accounts::Commands::OpenAccount.call(party_record_id: party.id)
  end
end
