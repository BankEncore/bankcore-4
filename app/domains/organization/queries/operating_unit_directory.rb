# frozen_string_literal: true

module Organization
  module Queries
    class OperatingUnitDirectory
      def self.call(status: nil, unit_type: nil)
        scope = Models::OperatingUnit.includes(:parent_operating_unit).order(:parent_operating_unit_id, :code)
        scope = scope.where(status: status) if status.present?
        scope = scope.where(unit_type: unit_type) if unit_type.present?
        scope
      end
    end
  end
end
