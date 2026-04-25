# frozen_string_literal: true

require "test_helper"

class PartySearchTest < ActiveSupport::TestCase
  test "searches by party id and name fields with bounded results" do
    party = Party::Commands::CreateParty.call(
      party_type: "individual",
      first_name: "Carmen",
      preferred_first_name: "Cami",
      last_name: "Servicing"
    )

    by_id = Party::Queries::PartySearch.call(query: party.id.to_s)
    assert_equal [ party.id ], by_id.rows.map(&:id)

    by_name = Party::Queries::PartySearch.call(query: "cami")
    assert_includes by_name.rows.map(&:id), party.id
    assert_equal 25, by_name.limit
  end
end
