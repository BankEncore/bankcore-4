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

  test "catalog entries declare required channel metadata" do
    valid_lifecycles = %w[pending_to_posted posted_immediately]
    valid_financial_impacts = %w[gl_posting optional_gl no_gl]
    valid_channels = Core::OperationalEvents::Commands::RecordEvent::CHANNELS

    Core::OperationalEvents::EventCatalog.all_entries.each do |entry|
      assert_includes valid_lifecycles, entry.lifecycle, "invalid lifecycle for #{entry.event_type}"
      assert entry.allowed_channels.present?, "missing allowed_channels for #{entry.event_type}"
      assert_empty entry.allowed_channels - valid_channels, "invalid allowed_channels for #{entry.event_type}"
      assert_includes valid_financial_impacts, entry.financial_impact, "invalid financial_impact for #{entry.event_type}"
      assert_includes [ true, false ], entry.customer_visible, "customer_visible must be explicit for #{entry.event_type}"
      assert_includes [ true, false ], entry.statement_visible, "statement_visible must be explicit for #{entry.event_type}"
      assert entry.payload_schema.present?, "missing payload_schema for #{entry.event_type}"
      assert entry.support_search_keys.present?, "missing support_search_keys for #{entry.event_type}"
    end
  end

  test "catalog financial impact is consistent with GL posting flag" do
    Core::OperationalEvents::EventCatalog.all_entries.each do |entry|
      if entry.posts_to_gl
        assert_includes %w[gl_posting optional_gl], entry.financial_impact,
          "GL-backed #{entry.event_type} must be gl_posting or optional_gl"
      else
        assert_equal "no_gl", entry.financial_impact,
          "no-GL #{entry.event_type} must declare no_gl financial impact"
      end
    end
  end

  test "catalog visibility and channel helpers return event types" do
    assert_includes Core::OperationalEvents::EventCatalog.statement_visible_event_types, "hold.placed"
    assert_not_includes Core::OperationalEvents::EventCatalog.statement_visible_event_types, "interest.accrued"
    assert_equal %w[hold.placed hold.released overdraft.nsf_denied],
      Core::OperationalEvents::EventCatalog.statement_visible_no_gl_event_types
    assert_includes Core::OperationalEvents::EventCatalog.customer_visible_event_types, "fee.assessed"
    assert_includes Core::OperationalEvents::EventCatalog.event_types_for_channel("branch"), "fee.waived"
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

  test "docs index metadata columns match EventCatalog" do
    rows_by_type = readme_index_rows_by_event_type

    Core::OperationalEvents::EventCatalog.all_entries.each do |entry|
      row = rows_by_type.fetch(entry.event_type)

      assert row.fetch(:record_command).include?(entry.record_command),
        "README record command for #{entry.event_type} should include #{entry.record_command}"
      assert_equal entry.lifecycle, extract_backticked_value(row.fetch(:lifecycle)),
        "README lifecycle mismatch for #{entry.event_type}"
      assert_equal entry.allowed_channels, extract_backticked_values(row.fetch(:channels)),
        "README channels mismatch for #{entry.event_type}"
      assert_equal yes_no(entry.customer_visible), row.fetch(:customer_visible),
        "README customer visibility mismatch for #{entry.event_type}"
      assert_equal yes_no(entry.statement_visible), row.fetch(:statement_visible),
        "README statement visibility mismatch for #{entry.event_type}"
    end
  end

  test "catalog specs declare metadata matching EventCatalog" do
    rows_by_type = readme_index_rows_by_event_type

    Core::OperationalEvents::EventCatalog.all_entries.each do |entry|
      values = spec_registry_values(rows_by_type.fetch(entry.event_type).fetch(:path))

      assert_equal entry.lifecycle, extract_backticked_value(values.fetch("Lifecycle")),
        "spec lifecycle mismatch for #{entry.event_type}"
      assert_equal entry.allowed_channels, extract_backticked_values(values.fetch("Allowed channels")),
        "spec allowed channels mismatch for #{entry.event_type}"
      assert_equal entry.financial_impact, extract_backticked_value(values.fetch("Financial impact")),
        "spec financial impact mismatch for #{entry.event_type}"
      assert_equal yes_no(entry.customer_visible), values.fetch("Customer visible"),
        "spec customer visibility mismatch for #{entry.event_type}"
      assert_equal yes_no(entry.statement_visible), values.fetch("Statement visible"),
        "spec statement visibility mismatch for #{entry.event_type}"
      assert_equal entry.payload_schema, extract_backticked_value(values.fetch("Payload schema")),
        "spec payload schema mismatch for #{entry.event_type}"
      assert_equal entry.support_search_keys, extract_backticked_values(values.fetch("Support search keys")),
        "spec support search keys mismatch for #{entry.event_type}"
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
    cells = line.split("|").map(&:strip)
    return unless cells.length >= 9 && cells[1].start_with?("[")

    {
      path: cells[1].match(/\[[^\]]+\]\(([^)]+)\)/)&.[](1),
      event_type: extract_backticked_value(cells[2]),
      gl_posting: cells[3],
      record_command: cells[4],
      lifecycle: cells[5],
      channels: cells[6],
      customer_visible: cells[7],
      statement_visible: cells[8]
    }
  end

  def spec_registry_event_type(relative_path)
    extract_backticked_value(spec_registry_values(relative_path).fetch("event_type", ""))
  end

  def spec_path(relative_path)
    DOCS_DIR.join(relative_path)
  end

  def extract_backticked_value(value)
    value.match(/`([^`]+)`/)&.[](1)
  end

  def extract_backticked_values(value)
    value.scan(/`([^`]+)`/).flatten
  end

  def spec_registry_values(relative_path)
    content = File.read(spec_path(relative_path))
    registry_section = content.split("## Registry", 2).fetch(1, "").split(/^## /, 2).first

    registry_section.lines.each_with_object({}) do |line, memo|
      next unless line.start_with?("|")

      cells = line.split("|").map(&:strip)
      next unless cells.length >= 3

      label = cells[1].gsub("*", "").gsub("`", "").strip
      memo[label] = cells[2]
    end
  end

  def yes_no(value)
    value ? "Yes" : "No"
  end
end
