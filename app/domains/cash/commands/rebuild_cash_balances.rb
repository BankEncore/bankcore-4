# frozen_string_literal: true

module Cash
  module Commands
    class RebuildCashBalances
      ReplayEntry = Struct.new(:business_date, :effective_at, :priority, :source_id, :entry_type, :record, keyword_init: true)
      PRIORITY_MOVEMENT = 1
      PRIORITY_TELLER_EVENT_PROJECTION = 2
      PRIORITY_COUNT = 3

      def self.call
        Cash::Models::CashBalance.transaction do
          Cash::Models::CashBalance.update_all(amount_minor_units: 0, last_cash_movement_id: nil, last_cash_count_id: nil)

          replay_entries.each do |entry|
            apply_replay_entry!(entry)
          end

          Cash::Models::CashBalance.order(:cash_location_id, :currency).to_a
        end
      end

      def self.replay_entries
        [
          *movement_entries,
          *teller_event_projection_entries,
          *count_entries
        ].sort_by { |entry| [ entry.business_date, entry.effective_at, entry.priority, entry.source_id ] }
      end
      private_class_method :replay_entries

      def self.movement_entries
        Cash::Models::CashMovement
          .where(status: Cash::Models::CashMovement::STATUS_COMPLETED)
          .map do |movement|
            ReplayEntry.new(
              business_date: movement.business_date,
              effective_at: movement.completed_at || movement.updated_at,
              priority: PRIORITY_MOVEMENT,
              source_id: movement.id,
              entry_type: :movement,
              record: movement
            )
          end
      end
      private_class_method :movement_entries

      def self.teller_event_projection_entries
        return [] unless defined?(Cash::Models::CashTellerEventProjection)

        Cash::Models::CashTellerEventProjection.all.map do |projection|
          ReplayEntry.new(
            business_date: projection.business_date,
            effective_at: projection.applied_at,
            priority: PRIORITY_TELLER_EVENT_PROJECTION,
            source_id: projection.id,
            entry_type: :teller_event_projection,
            record: projection
          )
        end
      end
      private_class_method :teller_event_projection_entries

      def self.count_entries
        Cash::Models::CashCount.all.map do |count|
          ReplayEntry.new(
            business_date: count.business_date,
            effective_at: count.created_at,
            priority: PRIORITY_COUNT,
            source_id: count.id,
            entry_type: :count,
            record: count
          )
        end
      end
      private_class_method :count_entries

      def self.apply_replay_entry!(entry)
        case entry.entry_type
        when :movement
          apply_movement_without_insufficient_check!(entry.record)
        when :teller_event_projection
          Cash::Services::BalanceProjector.apply_teller_event_projection!(entry.record)
        when :count
          Cash::Services::BalanceProjector.apply_count!(entry.record)
        else
          raise ArgumentError, "unknown cash balance replay entry #{entry.entry_type.inspect}"
        end
      end
      private_class_method :apply_replay_entry!

      def self.apply_movement_without_insufficient_check!(movement)
        amount = movement.amount_minor_units.to_i
        if movement.source_cash_location
          balance = Cash::Services::BalanceProjector.balance_for(movement.source_cash_location)
          balance.update!(
            amount_minor_units: balance.amount_minor_units.to_i - amount,
            last_cash_movement: movement
          )
        end
        return unless movement.destination_cash_location

        balance = Cash::Services::BalanceProjector.balance_for(movement.destination_cash_location)
        balance.update!(
          amount_minor_units: balance.amount_minor_units.to_i + amount,
          last_cash_movement: movement
        )
      end
      private_class_method :apply_movement_without_insufficient_check!
    end
  end
end
