# frozen_string_literal: true

require "test_helper"

class PartyUpdateContactPointTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::Rbac.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 9, 10))
    @party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Contact", last_name: "Member")
    @operator = Workspace::Models::Operator.create!(
      role: "supervisor",
      display_name: "Contact Supervisor",
      active: true,
      default_operating_unit: Organization::Services::DefaultOperatingUnit.branch
    )
  end

  test "adds and supersedes email contact with party audit rows" do
    first = Party::Commands::UpdateContactPoint.call(
      party_record_id: @party.id,
      contact_type: "email",
      purpose: Party::Models::PartyEmail::PURPOSE_PRIMARY,
      value: "first@example.test",
      idempotency_key: "email-first",
      actor_id: @operator.id
    )

    assert_equal :created, first[:outcome]
    assert_equal "first@example.test", first[:contact].email
    assert_equal Party::Models::PartyContactAudit::ACTION_ADDED, first[:audit].action

    second = Party::Commands::UpdateContactPoint.call(
      party_record_id: @party.id,
      contact_type: "email",
      purpose: Party::Models::PartyEmail::PURPOSE_PRIMARY,
      value: "second@example.test",
      idempotency_key: "email-second",
      actor_id: @operator.id
    )

    assert_equal :created, second[:outcome]
    assert_equal 1, @party.party_emails.active.where(purpose: Party::Models::PartyEmail::PURPOSE_PRIMARY).count
    assert_equal "second@example.test", @party.party_emails.active.first.email
    assert_equal Party::Models::PartyEmail::STATUS_INACTIVE, first[:contact].reload.status
    assert Party::Models::PartyContactAudit.exists?(action: Party::Models::PartyContactAudit::ACTION_SUPERSEDED)
  end

  test "adds address contact and replays idempotent request" do
    result = Party::Commands::UpdateContactPoint.call(
      party_record_id: @party.id,
      contact_type: "address",
      purpose: Party::Models::PartyAddress::PURPOSE_RESIDENTIAL,
      attributes: {
        line1: "100 Main St",
        city: "Boston",
        region: "MA",
        postal_code: "02110"
      },
      idempotency_key: "address-first",
      actor_id: @operator.id
    )
    assert_equal :created, result[:outcome]
    assert_equal "US", result[:contact].country

    replay = Party::Commands::UpdateContactPoint.call(
      party_record_id: @party.id,
      contact_type: "address",
      purpose: Party::Models::PartyAddress::PURPOSE_RESIDENTIAL,
      attributes: {
        line1: "100 Main St",
        city: "Boston",
        region: "MA",
        postal_code: "02110"
      },
      idempotency_key: "address-first",
      actor_id: @operator.id
    )
    assert_equal :replay, replay[:outcome]
    assert_equal result[:contact].id, replay[:contact].id
  end
end
