# frozen_string_literal: true

module Organization
  module Commands
    class CreateOperatingUnit
      class InvalidRequest < StandardError; end

      def self.call(attributes:)
        attrs = normalized_attributes(attributes)
        Models::OperatingUnit.create!(attrs)
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
        raise InvalidRequest, e.message
      end

      def self.normalized_attributes(attributes)
        attrs = attributes.to_h.symbolize_keys
        attrs[:code] = attrs[:code].to_s.strip.upcase
        attrs[:name] = attrs[:name].to_s.strip
        attrs[:parent_operating_unit_id] = attrs[:parent_operating_unit_id].presence
        attrs[:opened_on] = parse_date(attrs[:opened_on])
        attrs[:closed_on] = parse_date(attrs[:closed_on])
        attrs.slice(:code, :name, :unit_type, :status, :parent_operating_unit_id, :time_zone, :opened_on, :closed_on)
      end
      private_class_method :normalized_attributes

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
