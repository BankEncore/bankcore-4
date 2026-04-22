# frozen_string_literal: true

require "test_helper"

class PartyCreatePartyTest < ActiveSupport::TestCase
  test "creates individual party with derived name" do
    record = Party::Commands::CreateParty.call(
      party_type: "individual",
      first_name: "Jane",
      last_name: "Doe"
    )
    assert_equal "Jane Doe", record.name
    assert_equal "individual", record.party_type
    assert record.individual_profile
    assert_equal "Jane", record.individual_profile.first_name
  end

  test "name includes middle and suffix per ADR-0009" do
    record = Party::Commands::CreateParty.call(
      party_type: "individual",
      first_name: "Jane",
      middle_name: "Marie",
      last_name: "Doe",
      name_suffix: "Jr."
    )
    assert_equal "Jane Marie Doe, Jr.", record.name
  end

  test "rejects non-individual party types" do
    assert_raises(Party::Commands::CreateParty::UnsupportedPartyType) do
      Party::Commands::CreateParty.call(party_type: "organization", first_name: "X", last_name: "Y")
    end
  end

  test "FindParty returns record" do
    created = Party::Commands::CreateParty.call(party_type: "individual", first_name: "A", last_name: "B")
    found = Party::Queries::FindParty.by_id(created.id)
    assert_equal created.id, found.id
  end
end
