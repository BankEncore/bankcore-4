# frozen_string_literal: true

module Cash
  module Queries
    module LocationActivity
      module_function

      def call(cash_location_id:, limit: 50)
        location = Cash::Models::CashLocation.find(cash_location_id)
        movements = Cash::Models::CashMovement
          .where("source_cash_location_id = :id OR destination_cash_location_id = :id", id: location.id)
          .order(created_at: :desc, id: :desc)
          .limit(limit)
        counts = Cash::Models::CashCount
          .where(cash_location: location)
          .includes(:cash_variance)
          .order(created_at: :desc, id: :desc)
          .limit(limit)

        {
          location: location,
          movements: movements.to_a,
          counts: counts.to_a,
          variances: Cash::Models::CashVariance.where(cash_location: location).order(created_at: :desc, id: :desc).limit(limit).to_a
        }
      end
    end
  end
end
