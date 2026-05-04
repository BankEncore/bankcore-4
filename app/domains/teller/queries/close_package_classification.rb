# frozen_string_literal: true

module Teller
  module Queries
    # ADR-0041 T4.1: derived close-package buckets over existing rows. `EodReadiness` is the only
    # authority for `eod_ready` and blocker conjuncts; this query explains and classifies evidence.
    #
    # Summary operational-event buckets use primary classification only (one bucket per event row).
    # NSF (`overdraft.nsf_denied`) is exception, not posted summary.
    class ClosePackageClassification
      MAX_EVIDENCE_IDS = 200

      OVERRIDE_EVENT_TYPES = %w[override.requested override.approved].freeze

      def self.call(business_date:)
        new(business_date: business_date).call
      end

      def initialize(business_date:)
        @business_date = business_date
      end

      def call
        readiness = EodReadiness.call(business_date: @business_date)

        {
          readiness: readiness,
          actionable_close_package: actionable_close_package?(readiness),
          retrospective_only: readiness[:posting_day_closed],
          blockers: build_blockers(readiness),
          warnings: build_warnings(readiness),
          buckets: build_event_buckets.merge(held: build_held_bucket)
        }
      end

      private

      def actionable_close_package?(readiness)
        !readiness[:posting_day_closed]
      end

      def build_blockers(readiness)
        list = []
        unless readiness[:journal_totals_balanced]
          list << {
            code: "journal_imbalance",
            label: "Journal totals are not balanced for this business date.",
            total_debit_minor_units: readiness[:total_debit_minor_units],
            total_credit_minor_units: readiness[:total_credit_minor_units]
          }
        end
        unless readiness[:all_sessions_closed]
          ids = open_session_scope.order(:id).limit(MAX_EVIDENCE_IDS).pluck(:id)
          list << {
            code: "open_teller_sessions",
            label: "One or more teller sessions are open or pending supervisor.",
            count: readiness[:open_teller_sessions_count],
            teller_session_ids: ids
          }
        end
        pending_count = readiness[:pending_operational_events_count].to_i
        unless pending_count.zero?
          ids = pending_events_scope.order(:id).limit(MAX_EVIDENCE_IDS).pluck(:id)
          list << {
            code: "pending_operational_events",
            label: "One or more operational events are still pending.",
            count: pending_count,
            operational_event_ids: ids
          }
        end
        list
      end

      def build_warnings(readiness)
        readiness[:cash_eod_warnings].map do |code|
          {
            code: code,
            label: cash_warning_label(code),
            count: cash_warning_count(readiness, code)
          }
        end
      end

      def cash_warning_label(code)
        case code.to_s
        when "pending_cash_movements"
          "Pending cash movements awaiting approval."
        when "unresolved_cash_variances"
          "Unresolved or approved cash variances on this business date."
        else
          code.to_s.humanize
        end
      end

      def cash_warning_count(readiness, code)
        case code.to_s
        when "pending_cash_movements"
          readiness[:pending_cash_movements_count].to_i
        when "unresolved_cash_variances"
          readiness[:unresolved_cash_variances_count].to_i
        else
          0
        end
      end

      def build_event_buckets
        oe = Core::OperationalEvents::Models::OperationalEvent
        counts = Hash.new(0)
        ids = Hash.new { |h, k| h[k] = [] }

        oe.where(business_date: @business_date).order(:id).find_each do |event|
          bucket = primary_bucket_for(event)
          next if bucket.nil?

          counts[bucket] += 1
          list = ids[bucket]
          list << event.id if list.size < MAX_EVIDENCE_IDS
        end

        %i[posted pending reversed overridden exception].map do |key|
          [ key, { count: counts[key], operational_event_ids: ids[key] } ]
        end.to_h
      end

      # Loads rows twice for posted bucket counting — acceptable for Ops close package volume;
      # optimize with SQL CASE if needed later.
      def primary_bucket_for(event)
        return :pending if event.status == Core::OperationalEvents::Models::OperationalEvent::STATUS_PENDING
        return :reversed if event.event_type == "posting.reversal"
        return :overridden if OVERRIDE_EVENT_TYPES.include?(event.event_type.to_s)
        return :exception if event.event_type == "overdraft.nsf_denied"

        if event.status == Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED
          return :posted
        end

        nil
      end

      def build_held_bucket
        holds = held_scope.order(:id).limit(MAX_EVIDENCE_IDS)
        {
          count: held_scope.count,
          hold_ids: holds.pluck(:id)
        }
      end

      def held_scope
        Accounts::Models::Hold.where(status: Accounts::Models::Hold::STATUS_ACTIVE).where(
          [ <<~SQL.squish, { bd: @business_date } ]
            EXISTS (
              SELECT 1 FROM operational_events oe_pb
              WHERE oe_pb.id = holds.placed_by_operational_event_id
                AND oe_pb.business_date = :bd
            )
            OR EXISTS (
              SELECT 1 FROM operational_events oe_pf
              WHERE oe_pf.id = holds.placed_for_operational_event_id
                AND oe_pf.business_date = :bd
            )
          SQL
        )
      end

      def open_session_scope
        Teller::Models::TellerSession.where(
          status: [
            Teller::Models::TellerSession::STATUS_OPEN,
            Teller::Models::TellerSession::STATUS_PENDING_SUPERVISOR
          ]
        )
      end

      def pending_events_scope
        Core::OperationalEvents::Models::OperationalEvent.where(
          business_date: @business_date,
          status: Core::OperationalEvents::Models::OperationalEvent::STATUS_PENDING
        )
      end
    end
  end
end
