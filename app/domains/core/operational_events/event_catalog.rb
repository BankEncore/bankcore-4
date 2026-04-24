# frozen_string_literal: true

module Core
  module OperationalEvents
    # Code-first metadata for discovery and drift tests (ADR-0019). Not a second DB source of truth for event_type.
    module EventCatalog
      Entry = Data.define(
        :event_type,
        :category,
        :posts_to_gl,
        :record_command,
        :reversible_via_posting_reversal,
        :compensating_event_type,
        :description
      )

      ENTRIES = [
        Entry.new("deposit.accepted", "financial", true, "RecordEvent", true, "posting.reversal",
          "Cash or equivalent in to DDA"),
        Entry.new("withdrawal.posted", "financial", true, "RecordEvent", true, "posting.reversal",
          "Cash or equivalent out from DDA"),
        Entry.new("transfer.completed", "financial", true, "RecordEvent", true, "posting.reversal",
          "Transfer between DDAs"),
        Entry.new("posting.reversal", "financial", true, "RecordReversal", false, nil,
          "Compensating reversal journal for a reversible financial event"),
        Entry.new("fee.assessed", "financial", true, "RecordEvent", false, "fee.waived",
          "Deposit service charge assessed to DDA"),
        Entry.new("fee.waived", "financial", true, "RecordEvent", false, nil,
          "Waives a prior posted fee.assessed (reference_id = original event id)"),
        Entry.new("interest.accrued", "financial", true, "RecordEvent", true, "posting.reversal",
          "Accrues deposit interest expense and payable (system channel only; ADR-0021)"),
        Entry.new("interest.posted", "financial", true, "RecordEvent", true, "posting.reversal",
          "Pays a posted interest.accrued into DDA (reference_id = accrual event id; ADR-0021)"),
        Entry.new("teller.drawer.variance.posted", "financial", true, "RecordEvent", false, nil,
          "GL adjustment for non-zero teller drawer cash variance (system channel only; ADR-0020)"),
        Entry.new("hold.placed", "servicing", false, "PlaceHold", false, nil,
          "Posted hold on DDA (no GL posting)"),
        Entry.new("hold.released", "servicing", false, "ReleaseHold", false, nil,
          "Posted hold release (no GL posting)"),
        Entry.new("override.requested", "operational", false, "RecordControlEvent", false, nil,
          "Supervisor override requested"),
        Entry.new("override.approved", "operational", false, "RecordControlEvent", false, nil,
          "Supervisor override approved")
      ].freeze

      def self.all_entries
        ENTRIES
      end

      def self.entry_for(event_type)
        ENTRIES.find { |e| e.event_type == event_type.to_s }
      end

      def self.as_api_array
        ENTRIES.map do |e|
          {
            event_type: e.event_type,
            category: e.category,
            posts_to_gl: e.posts_to_gl,
            record_command: e.record_command,
            reversible_via_posting_reversal: e.reversible_via_posting_reversal,
            compensating_event_type: e.compensating_event_type,
            description: e.description
          }
        end
      end
    end
  end
end
