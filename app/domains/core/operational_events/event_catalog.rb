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
        :description,
        :lifecycle,
        :allowed_channels,
        :financial_impact,
        :customer_visible,
        :statement_visible,
        :payload_schema,
        :support_search_keys
      )

      ENTRIES = [
        Entry.new(
          event_type: "deposit.accepted",
          category: "financial",
          posts_to_gl: true,
          record_command: "RecordEvent",
          reversible_via_posting_reversal: true,
          compensating_event_type: "posting.reversal",
          description: "Cash or equivalent in to DDA",
          lifecycle: "pending_to_posted",
          allowed_channels: %w[teller api batch],
          financial_impact: "gl_posting",
          customer_visible: true,
          statement_visible: true,
          payload_schema: "docs/operational_events/deposit-accepted.md",
          support_search_keys: %w[source_account_id actor_id teller_session_id]
        ),
        Entry.new(
          event_type: "check.deposit.accepted",
          category: "financial",
          posts_to_gl: true,
          record_command: "AcceptCheckDeposit",
          reversible_via_posting_reversal: true,
          compensating_event_type: "posting.reversal",
          description: "Teller-accepted check deposit credited to DDA via deposited items clearing (ADR-0040)",
          lifecycle: "pending_to_posted",
          allowed_channels: %w[teller],
          financial_impact: "gl_posting",
          customer_visible: true,
          statement_visible: true,
          payload_schema: "docs/operational_events/check-deposit-accepted.md",
          support_search_keys: %w[source_account_id actor_id teller_session_id idempotency_key reference_id]
        ),
        Entry.new(
          event_type: "ach.credit.received",
          category: "financial",
          posts_to_gl: true,
          record_command: "Integration::Ach::Commands::IngestReceiptFile",
          reversible_via_posting_reversal: true,
          compensating_event_type: "posting.reversal",
          description: "Inbound ACH credit accepted for posting to an open DDA",
          lifecycle: "pending_to_posted",
          allowed_channels: %w[batch],
          financial_impact: "gl_posting",
          customer_visible: true,
          statement_visible: true,
          payload_schema: "docs/operational_events/ach-credit-received.md",
          support_search_keys: %w[source_account_id reference_id idempotency_key]
        ),
        Entry.new(
          event_type: "withdrawal.posted",
          category: "financial",
          posts_to_gl: true,
          record_command: "RecordEvent",
          reversible_via_posting_reversal: true,
          compensating_event_type: "posting.reversal",
          description: "Cash or equivalent out from DDA",
          lifecycle: "pending_to_posted",
          allowed_channels: %w[teller api batch],
          financial_impact: "gl_posting",
          customer_visible: true,
          statement_visible: true,
          payload_schema: "docs/operational_events/withdrawal-posted.md",
          support_search_keys: %w[source_account_id actor_id teller_session_id]
        ),
        Entry.new(
          event_type: "transfer.completed",
          category: "financial",
          posts_to_gl: true,
          record_command: "RecordEvent",
          reversible_via_posting_reversal: true,
          compensating_event_type: "posting.reversal",
          description: "Transfer between DDAs",
          lifecycle: "pending_to_posted",
          allowed_channels: %w[teller api batch],
          financial_impact: "gl_posting",
          customer_visible: true,
          statement_visible: true,
          payload_schema: "docs/operational_events/transfer-completed.md",
          support_search_keys: %w[source_account_id destination_account_id actor_id]
        ),
        Entry.new(
          event_type: "posting.reversal",
          category: "financial",
          posts_to_gl: true,
          record_command: "RecordReversal",
          reversible_via_posting_reversal: false,
          compensating_event_type: nil,
          description: "Compensating reversal journal for a reversible financial event",
          lifecycle: "pending_to_posted",
          allowed_channels: %w[teller branch api batch],
          financial_impact: "gl_posting",
          customer_visible: true,
          statement_visible: true,
          payload_schema: "docs/operational_events/compensating-reversal.md",
          support_search_keys: %w[source_account_id destination_account_id reversal_of_event_id actor_id]
        ),
        Entry.new(
          event_type: "fee.assessed",
          category: "financial",
          posts_to_gl: true,
          record_command: "RecordEvent",
          reversible_via_posting_reversal: false,
          compensating_event_type: "fee.waived",
          description: "Deposit service charge assessed to DDA",
          lifecycle: "pending_to_posted",
          allowed_channels: %w[teller api batch system],
          financial_impact: "gl_posting",
          customer_visible: true,
          statement_visible: true,
          payload_schema: "docs/operational_events/fee-assessed.md",
          support_search_keys: %w[source_account_id reference_id actor_id]
        ),
        Entry.new(
          event_type: "fee.waived",
          category: "financial",
          posts_to_gl: true,
          record_command: "RecordEvent",
          reversible_via_posting_reversal: false,
          compensating_event_type: nil,
          description: "Waives a prior posted fee.assessed (reference_id = original event id)",
          lifecycle: "pending_to_posted",
          allowed_channels: %w[teller branch api batch],
          financial_impact: "gl_posting",
          customer_visible: true,
          statement_visible: true,
          payload_schema: "docs/operational_events/fee-waived.md",
          support_search_keys: %w[source_account_id reference_id actor_id]
        ),
        Entry.new(
          event_type: "interest.accrued",
          category: "financial",
          posts_to_gl: true,
          record_command: "RecordEvent",
          reversible_via_posting_reversal: true,
          compensating_event_type: "posting.reversal",
          description: "Accrues deposit interest expense and payable (system channel only; ADR-0021)",
          lifecycle: "pending_to_posted",
          allowed_channels: %w[system],
          financial_impact: "gl_posting",
          customer_visible: false,
          statement_visible: false,
          payload_schema: "docs/operational_events/interest-accrued.md",
          support_search_keys: %w[source_account_id reference_id]
        ),
        Entry.new(
          event_type: "interest.posted",
          category: "financial",
          posts_to_gl: true,
          record_command: "RecordEvent",
          reversible_via_posting_reversal: true,
          compensating_event_type: "posting.reversal",
          description: "Pays a posted interest.accrued into DDA (reference_id = accrual event id; ADR-0021)",
          lifecycle: "pending_to_posted",
          allowed_channels: %w[system],
          financial_impact: "gl_posting",
          customer_visible: true,
          statement_visible: true,
          payload_schema: "docs/operational_events/interest-posted.md",
          support_search_keys: %w[source_account_id reference_id]
        ),
        Entry.new(
          event_type: "teller.drawer.variance.posted",
          category: "financial",
          posts_to_gl: true,
          record_command: "RecordEvent",
          reversible_via_posting_reversal: false,
          compensating_event_type: nil,
          description: "GL adjustment for non-zero teller drawer cash variance (system channel only; ADR-0020)",
          lifecycle: "pending_to_posted",
          allowed_channels: %w[system],
          financial_impact: "optional_gl",
          customer_visible: false,
          statement_visible: false,
          payload_schema: "docs/operational_events/teller-drawer-variance-posted.md",
          support_search_keys: %w[teller_session_id reference_id]
        ),
        Entry.new(
          event_type: "cash.variance.posted",
          category: "financial",
          posts_to_gl: true,
          record_command: "Cash::Commands::ApproveCashVariance",
          reversible_via_posting_reversal: false,
          compensating_event_type: nil,
          description: "GL adjustment for approved Cash-domain location variance (system channel only; ADR-0031)",
          lifecycle: "pending_to_posted",
          allowed_channels: %w[system],
          financial_impact: "gl_posting",
          customer_visible: false,
          statement_visible: false,
          payload_schema: "docs/operational_events/cash-variance-posted.md",
          support_search_keys: %w[reference_id actor_id]
        ),
        Entry.new(
          event_type: "cash.shipment.received",
          category: "financial",
          posts_to_gl: true,
          record_command: "Cash::Commands::ReceiveExternalCashShipment",
          reversible_via_posting_reversal: true,
          compensating_event_type: "posting.reversal",
          description: "External Fed or correspondent cash shipment received into branch vault custody",
          lifecycle: "pending_to_posted",
          allowed_channels: %w[branch],
          financial_impact: "gl_posting",
          customer_visible: false,
          statement_visible: false,
          payload_schema: "docs/operational_events/cash-shipment-received.md",
          support_search_keys: %w[reference_id actor_id idempotency_key]
        ),
        Entry.new(
          event_type: "cash.movement.completed",
          category: "operational",
          posts_to_gl: false,
          record_command: "Cash::Commands::TransferCash",
          reversible_via_posting_reversal: false,
          compensating_event_type: nil,
          description: "Internal cash custody movement completed without GL posting",
          lifecycle: "posted_immediately",
          allowed_channels: %w[teller branch system],
          financial_impact: "no_gl",
          customer_visible: false,
          statement_visible: false,
          payload_schema: "docs/operational_events/cash-movement-completed.md",
          support_search_keys: %w[reference_id actor_id]
        ),
        Entry.new(
          event_type: "cash.count.recorded",
          category: "operational",
          posts_to_gl: false,
          record_command: "Cash::Commands::RecordCashCount",
          reversible_via_posting_reversal: false,
          compensating_event_type: "cash.variance.posted",
          description: "Cash location count recorded; variance may be approved and posted separately",
          lifecycle: "posted_immediately",
          allowed_channels: %w[teller branch system],
          financial_impact: "no_gl",
          customer_visible: false,
          statement_visible: false,
          payload_schema: "docs/operational_events/cash-count-recorded.md",
          support_search_keys: %w[reference_id actor_id]
        ),
        Entry.new(
          event_type: "hold.placed",
          category: "servicing",
          posts_to_gl: false,
          record_command: "PlaceHold",
          reversible_via_posting_reversal: false,
          compensating_event_type: nil,
          description: "Posted hold on DDA (no GL posting)",
          lifecycle: "posted_immediately",
          allowed_channels: %w[teller branch api batch],
          financial_impact: "no_gl",
          customer_visible: true,
          statement_visible: true,
          payload_schema: "docs/operational_events/hold-placed.md",
          support_search_keys: %w[source_account_id actor_id reference_id]
        ),
        Entry.new(
          event_type: "hold.released",
          category: "servicing",
          posts_to_gl: false,
          record_command: "ReleaseHold",
          reversible_via_posting_reversal: false,
          compensating_event_type: nil,
          description: "Posted hold release (no GL posting)",
          lifecycle: "posted_immediately",
          allowed_channels: %w[teller branch api batch],
          financial_impact: "no_gl",
          customer_visible: true,
          statement_visible: true,
          payload_schema: "docs/operational_events/hold-released.md",
          support_search_keys: %w[source_account_id reference_id actor_id]
        ),
        Entry.new(
          event_type: "override.requested",
          category: "operational",
          posts_to_gl: false,
          record_command: "RecordControlEvent",
          reversible_via_posting_reversal: false,
          compensating_event_type: nil,
          description: "Supervisor override requested",
          lifecycle: "posted_immediately",
          allowed_channels: %w[teller branch batch],
          financial_impact: "no_gl",
          customer_visible: false,
          statement_visible: false,
          payload_schema: "docs/operational_events/override-requested.md",
          support_search_keys: %w[reference_id actor_id]
        ),
        Entry.new(
          event_type: "override.approved",
          category: "operational",
          posts_to_gl: false,
          record_command: "RecordControlEvent",
          reversible_via_posting_reversal: false,
          compensating_event_type: nil,
          description: "Supervisor override approved",
          lifecycle: "posted_immediately",
          allowed_channels: %w[teller branch batch],
          financial_impact: "no_gl",
          customer_visible: false,
          statement_visible: false,
          payload_schema: "docs/operational_events/override-approved.md",
          support_search_keys: %w[reference_id actor_id]
        ),
        Entry.new(
          event_type: "overdraft.nsf_denied",
          category: "operational",
          posts_to_gl: false,
          record_command: "RecordControlEvent",
          reversible_via_posting_reversal: false,
          compensating_event_type: "fee.assessed",
          description: "Denied overdraft/NSF debit attempt; may trigger linked NSF fee",
          lifecycle: "posted_immediately",
          allowed_channels: %w[teller api batch],
          financial_impact: "no_gl",
          customer_visible: true,
          statement_visible: true,
          payload_schema: "docs/operational_events/overdraft-nsf-denied.md",
          support_search_keys: %w[source_account_id destination_account_id reference_id actor_id]
        ),
        Entry.new(
          event_type: "account.restricted",
          category: "account_control",
          posts_to_gl: false,
          record_command: "Accounts::Commands::RestrictAccount",
          reversible_via_posting_reversal: false,
          compensating_event_type: "account.unrestricted",
          description: "Account restriction or freeze applied through Branch servicing",
          lifecycle: "posted_immediately",
          allowed_channels: %w[branch],
          financial_impact: "no_gl",
          customer_visible: false,
          statement_visible: false,
          payload_schema: "docs/operational_events/account-restricted.md",
          support_search_keys: %w[source_account_id reference_id actor_id]
        ),
        Entry.new(
          event_type: "account.unrestricted",
          category: "account_control",
          posts_to_gl: false,
          record_command: "Accounts::Commands::UnrestrictAccount",
          reversible_via_posting_reversal: false,
          compensating_event_type: nil,
          description: "Forward release of an account restriction",
          lifecycle: "posted_immediately",
          allowed_channels: %w[branch],
          financial_impact: "no_gl",
          customer_visible: false,
          statement_visible: false,
          payload_schema: "docs/operational_events/account-unrestricted.md",
          support_search_keys: %w[source_account_id reference_id actor_id]
        ),
        Entry.new(
          event_type: "account.closed",
          category: "account_control",
          posts_to_gl: false,
          record_command: "Accounts::Commands::CloseAccount",
          reversible_via_posting_reversal: false,
          compensating_event_type: nil,
          description: "Explicit account close after lifecycle preconditions pass",
          lifecycle: "posted_immediately",
          allowed_channels: %w[branch],
          financial_impact: "no_gl",
          customer_visible: false,
          statement_visible: false,
          payload_schema: "docs/operational_events/account-closed.md",
          support_search_keys: %w[source_account_id reference_id actor_id]
        )
      ].freeze

      def self.all_entries
        ENTRIES
      end

      def self.entry_for(event_type)
        ENTRIES.find { |e| e.event_type == event_type.to_s }
      end

      def self.statement_visible_event_types
        ENTRIES.select(&:statement_visible).map(&:event_type)
      end

      def self.statement_visible_no_gl_event_types
        ENTRIES.select { |e| e.statement_visible && e.financial_impact == "no_gl" }.map(&:event_type)
      end

      def self.customer_visible_event_types
        ENTRIES.select(&:customer_visible).map(&:event_type)
      end

      def self.entries_for_channel(channel)
        ENTRIES.select { |e| e.allowed_channels.include?(channel.to_s) }
      end

      def self.event_types_for_channel(channel)
        entries_for_channel(channel).map(&:event_type)
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
            description: e.description,
            lifecycle: e.lifecycle,
            allowed_channels: e.allowed_channels,
            financial_impact: e.financial_impact,
            customer_visible: e.customer_visible,
            statement_visible: e.statement_visible,
            payload_schema: e.payload_schema,
            support_search_keys: e.support_search_keys
          }
        end
      end
    end
  end
end
