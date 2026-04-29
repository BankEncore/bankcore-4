# frozen_string_literal: true

module Cash
  module Commands
    class RebuildCashBalances
      def self.call
        Cash::Models::CashBalance.transaction do
          Cash::Models::CashBalance.update_all(amount_minor_units: 0, last_cash_movement_id: nil, last_cash_count_id: nil)

          Cash::Models::CashMovement
            .where(status: Cash::Models::CashMovement::STATUS_COMPLETED)
            .order(:business_date, :id)
            .find_each do |movement|
              apply_movement_without_insufficient_check!(movement)
            end

          Cash::Models::CashCount.order(:business_date, :id).find_each do |count|
            Cash::Services::BalanceProjector.apply_count!(count)
          end

          Cash::Models::CashBalance.order(:cash_location_id, :currency).to_a
        end
      end

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
