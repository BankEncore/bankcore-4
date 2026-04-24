# frozen_string_literal: true

require "test_helper"

class CoreOperationalEventsEventCatalogTest < ActiveSupport::TestCase
  test "every posting registry handler has catalog entry with posts_to_gl" do
    Core::Posting::PostingRules::Registry::HANDLERS.each_key do |event_type|
      entry = Core::OperationalEvents::EventCatalog.entry_for(event_type)
      assert entry, "missing EventCatalog entry for #{event_type}"
      assert entry.posts_to_gl, "catalog must mark #{event_type} as posts_to_gl for PostingRules handler"
    end
  end

  test "fee types appear in API array" do
    types = Core::OperationalEvents::EventCatalog.as_api_array.map { |h| h[:event_type] }
    assert_includes types, "fee.assessed"
    assert_includes types, "fee.waived"
  end

  test "teller.drawer.variance.posted appears in API array" do
    types = Core::OperationalEvents::EventCatalog.as_api_array.map { |h| h[:event_type] }
    assert_includes types, "teller.drawer.variance.posted"
  end

  test "interest types appear in API array" do
    types = Core::OperationalEvents::EventCatalog.as_api_array.map { |h| h[:event_type] }
    assert_includes types, "interest.accrued"
    assert_includes types, "interest.posted"
  end

  test "overdraft NSF denial appears in API array as no-GL event" do
    entry = Core::OperationalEvents::EventCatalog.entry_for("overdraft.nsf_denied")
    assert entry
    assert_not entry.posts_to_gl
    assert_equal "RecordControlEvent", entry.record_command
  end
end
