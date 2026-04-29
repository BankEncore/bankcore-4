# frozen_string_literal: true

module Organization
  module Commands
    class CloseOperatingUnit
      class InvalidRequest < StandardError; end

      def self.call(operating_unit_id:, closed_on:)
        unit = Models::OperatingUnit.find(operating_unit_id)
        date = parse_date(closed_on)
        raise InvalidRequest, "closed_on is required" if date.blank?
        raise InvalidRequest, "active child operating units must be closed first" if active_children?(unit)
        raise InvalidRequest, "active cash locations must be deactivated first" if active_cash_locations?(unit)

        unit.update!(status: Models::OperatingUnit::STATUS_CLOSED, closed_on: date)
        unit
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
        raise InvalidRequest, e.message
      end

      def self.active_children?(unit)
        unit.child_operating_units.where(status: Models::OperatingUnit::STATUS_ACTIVE).exists?
      end
      private_class_method :active_children?

      def self.active_cash_locations?(unit)
        Cash::Models::CashLocation.where(
          operating_unit_id: unit.id,
          status: Cash::Models::CashLocation::STATUS_ACTIVE
        ).exists?
      end
      private_class_method :active_cash_locations?

      def self.parse_date(value)
        return nil if value.blank?

        Date.iso8601(value.to_s)
      rescue ArgumentError, TypeError
        raise InvalidRequest, "closed_on must be a valid ISO 8601 date"
      end
      private_class_method :parse_date
    end
  end
end
