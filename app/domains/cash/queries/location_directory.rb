# frozen_string_literal: true

module Cash
  module Queries
    class LocationDirectory
      def self.call(operating_unit_id: nil, location_type: nil, status: nil)
        scope = Models::CashLocation
          .includes(:operating_unit, :responsible_operator, :parent_cash_location, :cash_balance)
          .order(:operating_unit_id, :location_type, :drawer_code, :name)
        scope = scope.where(operating_unit_id: operating_unit_id) if operating_unit_id.present?
        scope = scope.where(location_type: location_type) if location_type.present?
        scope = scope.where(status: status) if status.present?
        scope
      end
    end
  end
end
