# frozen_string_literal: true

module Organization
  module Commands
    class UpdateOperatingUnit
      PROTECTED_CODES = [
        Services::DefaultOperatingUnit::INSTITUTION_CODE,
        Services::DefaultOperatingUnit::BRANCH_CODE
      ].freeze

      class InvalidRequest < StandardError; end

      def self.call(operating_unit_id:, attributes:)
        unit = Models::OperatingUnit.find(operating_unit_id)
        attrs = normalized_attributes(attributes)
        validate_code_change!(unit, attrs)
        validate_parent!(unit, attrs[:parent_operating_unit_id])
        validate_close_transition!(unit, attrs)
        unit.update!(attrs)
        unit
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ActiveRecord::RecordNotUnique => e
        raise InvalidRequest, e.message
      end

      def self.normalized_attributes(attributes)
        attrs = attributes.to_h.symbolize_keys
        attrs[:code] = attrs[:code].to_s.strip.upcase if attrs.key?(:code)
        attrs[:name] = attrs[:name].to_s.strip if attrs.key?(:name)
        attrs[:parent_operating_unit_id] = attrs[:parent_operating_unit_id].presence if attrs.key?(:parent_operating_unit_id)
        attrs[:opened_on] = parse_date(attrs[:opened_on]) if attrs.key?(:opened_on)
        attrs[:closed_on] = parse_date(attrs[:closed_on]) if attrs.key?(:closed_on)
        attrs.slice(:code, :name, :unit_type, :status, :parent_operating_unit_id, :time_zone, :opened_on, :closed_on)
      end
      private_class_method :normalized_attributes

      def self.validate_code_change!(unit, attrs)
        return unless attrs.key?(:code)
        return if attrs[:code] == unit.code
        return unless PROTECTED_CODES.include?(unit.code)

        raise InvalidRequest, "Seeded operating unit code #{unit.code} cannot be changed"
      end
      private_class_method :validate_code_change!

      def self.validate_parent!(unit, parent_id)
        return if parent_id.blank?

        parent = Models::OperatingUnit.find(parent_id)
        current = parent
        while current
          if current.id == unit.id
            raise InvalidRequest, "parent operating unit cannot be a descendant of this unit"
          end
          current = current.parent_operating_unit
        end
      end
      private_class_method :validate_parent!

      def self.validate_close_transition!(unit, attrs)
        return unless attrs[:status] == Models::OperatingUnit::STATUS_CLOSED
        return if unit.status == Models::OperatingUnit::STATUS_CLOSED
        raise InvalidRequest, "closed_on is required" if attrs[:closed_on].blank?
        if unit.child_operating_units.where(status: Models::OperatingUnit::STATUS_ACTIVE).exists?
          raise InvalidRequest, "active child operating units must be closed first"
        end
        if Cash::Models::CashLocation.where(
          operating_unit_id: unit.id,
          status: Cash::Models::CashLocation::STATUS_ACTIVE
        ).exists?
          raise InvalidRequest, "active cash locations must be deactivated first"
        end
      end
      private_class_method :validate_close_transition!

      def self.parse_date(value)
        return nil if value.blank?

        Date.iso8601(value.to_s)
      rescue ArgumentError, TypeError
        raise InvalidRequest, "Dates must be valid ISO 8601 values"
      end
      private_class_method :parse_date
    end
  end
end
