# frozen_string_literal: true

namespace :spike do
  desc "Print T1 check deposit integration checklist (docs/spikes/check-deposit-t1-vertical-slice.md)"
  task check_deposit_t1: :environment do
    root = Rails.root
    paths = [
      "docs/spikes/check-deposit-t1-vertical-slice.md",
      "docs/concepts/303-bank-transaction-capability-taxonomy.md",
      "app/domains/core/operational_events/event_catalog.rb",
      "app/domains/core/operational_events/commands/record_event.rb",
      "app/domains/core/posting/posting_rules/registry.rb",
      "app/domains/core/posting/commands/post_event.rb",
      "app/domains/cash/services/teller_event_projector.rb",
      "app/domains/teller/queries/expected_cash_for_session.rb",
      "app/domains/accounts/commands/place_hold.rb",
      "docs/operational_events/README.md",
      "test/domains/core/operational_events/event_catalog_test.rb"
    ]

    puts <<~BANNER
      [spike:check_deposit_t1] T1 check deposit — integration touchpoints
      Full narrative: #{root.join("docs/spikes/check-deposit-t1-vertical-slice.md")}
    BANNER

    paths.each do |rel|
      abs = root.join(rel)
      flag = abs.exist? ? "ok" : "MISSING"
      puts format("%<flag>-7s %<rel>s", flag: flag, rel: rel)
    end

    puts "\nNext: draft ADR for event shape + availability; then catalog + RecordEvent + PostingRules together."
  end
end
