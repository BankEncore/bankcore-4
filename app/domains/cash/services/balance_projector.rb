# frozen_string_literal: true

module Cash
  module Services
    module BalanceProjector
      module_function

      def balance_for(location)
        Cash::Models::CashBalance.lock.find_or_create_by!(cash_location: location, currency: location.currency) do |balance|
          balance.amount_minor_units = 0
        end
      end

      def apply_completed_movement!(movement)
        amount = movement.amount_minor_units.to_i
        if movement.source_cash_location
          source_balance = balance_for(movement.source_cash_location)
          if source_balance.amount_minor_units.to_i < amount
            raise Cash::Commands::TransferCash::InvalidRequest, "source cash balance is insufficient"
          end
          source_balance.update!(
            amount_minor_units: source_balance.amount_minor_units.to_i - amount,
            last_cash_movement: movement
          )
        end

        return unless movement.destination_cash_location

        destination_balance = balance_for(movement.destination_cash_location)
        destination_balance.update!(
          amount_minor_units: destination_balance.amount_minor_units.to_i + amount,
          last_cash_movement: movement
        )
      end

      def apply_count!(count)
        balance = balance_for(count.cash_location)
        balance.update!(
          amount_minor_units: count.counted_amount_minor_units.to_i,
          last_cash_count: count
        )
      end
    end
  end
end
