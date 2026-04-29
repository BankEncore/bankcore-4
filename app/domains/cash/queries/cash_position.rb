# frozen_string_literal: true

module Cash
  module Queries
    module CashPosition
      module_function

      def call(operating_unit_id: nil, currency: "USD")
        scope = Cash::Models::CashLocation
          .includes(:cash_balance, :responsible_operator, :operating_unit)
          .order(:location_type, :drawer_code, :id)
        scope = scope.where(operating_unit_id: operating_unit_id) if operating_unit_id.present?

        scope.map do |location|
          balance = location.cash_balance || Cash::Models::CashBalance.new(amount_minor_units: 0, currency: currency)
          {
            id: location.id,
            location_type: location.location_type,
            name: location.name,
            drawer_code: location.drawer_code,
            status: location.status,
            operating_unit_id: location.operating_unit_id,
            responsible_operator_id: location.responsible_operator_id,
            currency: balance.currency,
            amount_minor_units: balance.amount_minor_units.to_i
          }
        end
      end
    end
  end
end
