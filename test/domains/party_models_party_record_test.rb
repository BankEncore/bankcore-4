# frozen_string_literal: true

require "test_helper"

class PartyModelsPartyRecordTest < ActiveSupport::TestCase
  test "Party::Models::PartyRecord autoloads from app/domains" do
    assert_equal "Party::Models::PartyRecord", Party::Models::PartyRecord.name
  end
end
