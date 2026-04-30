# frozen_string_literal: true

module Teller
  module Queries
    class SupervisorControlCatalog
      Control = Data.define(:key, :label, :capability_code, :owner_command, :evidence_fields, :no_self_approval)
      Result = Data.define(:controls, :pending)

      CONTROLS = [
        Control.new(
          key: :hold_release,
          label: "Hold release",
          capability_code: Workspace::Authorization::CapabilityRegistry::HOLD_RELEASE,
          owner_command: "Accounts::Commands::ReleaseHold",
          evidence_fields: %w[hold_id operational_event_id actor_id business_date idempotency_key],
          no_self_approval: false
        ),
        Control.new(
          key: :fee_waiver,
          label: "Fee waiver",
          capability_code: Workspace::Authorization::CapabilityRegistry::FEE_WAIVE,
          owner_command: "Core::OperationalEvents::Commands::RecordEvent",
          evidence_fields: %w[operational_event_id reference_id actor_id business_date posting_batch_ids],
          no_self_approval: false
        ),
        Control.new(
          key: :reversal,
          label: "Reversal",
          capability_code: Workspace::Authorization::CapabilityRegistry::REVERSAL_CREATE,
          owner_command: "Core::OperationalEvents::Commands::RecordReversal",
          evidence_fields: %w[operational_event_id reversal_of_event_id actor_id business_date posting_batch_ids],
          no_self_approval: false
        ),
        Control.new(
          key: :teller_variance,
          label: "Teller variance approval",
          capability_code: Workspace::Authorization::CapabilityRegistry::TELLER_SESSION_VARIANCE_APPROVE,
          owner_command: "Teller::Commands::ApproveSessionVariance",
          evidence_fields: %w[teller_session_id supervisor_operator_id supervisor_approved_at variance_minor_units],
          no_self_approval: false
        ),
        Control.new(
          key: :cash_movement,
          label: "Cash movement approval",
          capability_code: Workspace::Authorization::CapabilityRegistry::CASH_MOVEMENT_APPROVE,
          owner_command: "Cash::Commands::ApproveCashMovement",
          evidence_fields: %w[cash_movement_id approving_actor_id approved_at operational_event_id],
          no_self_approval: true
        ),
        Control.new(
          key: :cash_variance,
          label: "Cash variance approval",
          capability_code: Workspace::Authorization::CapabilityRegistry::CASH_VARIANCE_APPROVE,
          owner_command: "Cash::Commands::ApproveCashVariance",
          evidence_fields: %w[cash_variance_id approving_actor_id approved_at cash_variance_posted_event_id],
          no_self_approval: true
        ),
        Control.new(
          key: :event_posting,
          label: "Pending event posting",
          capability_code: Workspace::Authorization::CapabilityRegistry::OPERATIONAL_EVENT_VIEW,
          owner_command: "Core::Posting::Commands::PostEvent",
          evidence_fields: %w[operational_event_id event_status posting_batch_ids journal_entry_ids],
          no_self_approval: false
        )
      ].freeze

      def self.call(...)
        new(...).call
      end

      def initialize(operating_unit_id: nil, limit: 10)
        @operating_unit_id = operating_unit_id
        @limit = limit.to_i.clamp(1, 25)
      end

      def call
        Result.new(
          controls: CONTROLS,
          pending: {
            teller_variances: pending_teller_variances,
            cash_movements: pending_cash_approvals.fetch(:movements),
            cash_variances: pending_cash_approvals.fetch(:variances),
            active_holds: active_holds,
            reversible_events: reversible_events,
            pending_events: pending_events
          }
        )
      end

      private

      attr_reader :operating_unit_id, :limit

      def pending_teller_variances
        scope = Teller::Models::TellerSession
          .where(status: Teller::Models::TellerSession::STATUS_PENDING_SUPERVISOR)
          .includes(:supervisor_operator)
          .order(:opened_at, :id)
        scope = scope.where(operating_unit_id: operating_unit_id) if operating_unit_id.present?
        scope.limit(limit).to_a
      end

      def pending_cash_approvals
        @pending_cash_approvals ||= Cash::Queries::PendingCashApprovals.call(operating_unit_id: operating_unit_id)
      end

      def active_holds
        Accounts::Models::Hold
          .where(status: Accounts::Models::Hold::STATUS_ACTIVE)
          .includes(:deposit_account)
          .order(:created_at, :id)
          .limit(limit)
          .to_a
      end

      def reversible_events
        Core::OperationalEvents::Models::OperationalEvent
          .where(status: Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED, reversed_by_event_id: nil)
          .where(event_type: Core::OperationalEvents::EventCatalog.all_entries.select(&:reversible_via_posting_reversal).map(&:event_type))
          .order(id: :desc)
          .limit(limit)
          .to_a
      end

      def pending_events
        scope = Core::OperationalEvents::Models::OperationalEvent
          .where(status: Core::OperationalEvents::Models::OperationalEvent::STATUS_PENDING)
          .order(:business_date, :id)
        scope = scope.where(operating_unit_id: operating_unit_id) if operating_unit_id.present?
        scope.limit(limit).to_a
      end
    end
  end
end
