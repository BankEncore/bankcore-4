# frozen_string_literal: true

require "test_helper"

class CoreOperationalEventsEventCatalogTest < ActiveSupport::TestCase
  DOCS_DIR = Rails.root.join("docs/operational_events")
  NON_CATALOG_SPEC_FILES = %w[
    teller-session-opened.md
    teller-session-closed.md
  ].freeze

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

  test "catalog event types are unique" do
    event_types = catalog_event_types
    assert_equal event_types.uniq, event_types, "EventCatalog contains duplicate event_type values"
  end

  test "every GL-backed catalog entry has posting registry handler" do
    Core::OperationalEvents::EventCatalog.all_entries.each do |entry|
      next unless entry.posts_to_gl

      assert Core::Posting::PostingRules::Registry::HANDLERS.key?(entry.event_type),
        "missing PostingRules handler for GL-backed catalog entry #{entry.event_type}"
    end
  end

  test "catalog entries are covered by operational event docs index and specs" do
    rows_by_type = readme_index_rows_by_event_type

    Core::OperationalEvents::EventCatalog.all_entries.each do |entry|
      row = rows_by_type[entry.event_type]

      assert row, "missing docs/operational_events/README.md index row for #{entry.event_type}"
      assert row.fetch(:path).present?, "missing spec link for #{entry.event_type}"
      assert spec_path(row.fetch(:path)).exist?, "missing docs/operational_events/#{row.fetch(:path)} for #{entry.event_type}"
    end
  end

  test "operational event docs index links point to existing spec files" do
    readme_index_rows.each do |row|
      assert spec_path(row.fetch(:path)).exist?,
        "docs/operational_events/README.md links to missing file #{row.fetch(:path)}"
    end
  end

  test "catalog spec registry event_type matches catalog entry" do
    rows_by_type = readme_index_rows_by_event_type

    Core::OperationalEvents::EventCatalog.all_entries.each do |entry|
      row = rows_by_type.fetch(entry.event_type)
      declared = spec_registry_event_type(row.fetch(:path))

      assert_equal entry.event_type, declared,
        "docs/operational_events/#{row.fetch(:path)} declares #{declared.inspect}, expected #{entry.event_type.inspect}"
    end
  end

  test "docs index GL posting column matches EventCatalog posts_to_gl" do
    rows_by_type = readme_index_rows_by_event_type

    Core::OperationalEvents::EventCatalog.all_entries.each do |entry|
      row = rows_by_type.fetch(entry.event_type)
      gl_posting = row.fetch(:gl_posting)

      if entry.posts_to_gl
        assert gl_posting.start_with?("Yes"),
          "README GL posting column for #{entry.event_type} should start with Yes, was #{gl_posting.inspect}"
      else
        assert gl_posting.start_with?("No"),
          "README GL posting column for #{entry.event_type} should start with No, was #{gl_posting.inspect}"
      end
    end
  end

  test "non-catalog operational event docs are explicitly allowed" do
    catalog_spec_files = readme_index_rows_by_event_type.values.map { |row| row.fetch(:path) }
    indexed_spec_files = readme_index_rows.map { |row| row.fetch(:path) }
    extra_spec_files = indexed_spec_files - catalog_spec_files

    assert_empty extra_spec_files - NON_CATALOG_SPEC_FILES,
      "README indexes non-catalog operational event docs without allowlist entry"
  end

  private

  def catalog_event_types
    Core::OperationalEvents::EventCatalog.all_entries.map(&:event_type)
  end

  def readme_index_rows_by_event_type
    readme_index_rows.each_with_object({}) do |row, memo|
      memo[row.fetch(:event_type)] = row if row.fetch(:event_type).present?
    end
  end

  def readme_index_rows
    @readme_index_rows ||= begin
      readme_path = DOCS_DIR.join("README.md")

      File.readlines(readme_path).filter_map do |line|
        parse_readme_index_row(line)
      end
    end
  end

  def parse_readme_index_row(line)
    match = line.match(/\|\s*\[[^\]]+\]\(([^)]+)\)\s*\|\s*(.*?)\s*\|\s*(.*?)\s*\|\s*(.*?)\s*\|/)
    return unless match

    {
      path: match[1],
      event_type: extract_backticked_value(match[2]),
      gl_posting: match[3].strip,
      record_command: match[4].strip
    }
  end

  def spec_registry_event_type(relative_path)
    content = File.read(spec_path(relative_path))
    registry_section = content.split("## Registry", 2).fetch(1, "")
    row = registry_section.lines.find { |line| line.include?("**`event_type`**") }
    value_cell = row&.split("|")&.[](2)

    extract_backticked_value(value_cell.to_s)
  end

  def spec_path(relative_path)
    DOCS_DIR.join(relative_path)
  end

  def extract_backticked_value(value)
    value.match(/`([^`]+)`/)&.[](1)
  end
end
