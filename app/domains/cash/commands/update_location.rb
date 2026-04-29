# frozen_string_literal: true

module Cash
  module Commands
    class UpdateLocation
      class InvalidRequest < StandardError; end

      def self.call(cash_location_id:, attributes:)
        location = Models::CashLocation.find(cash_location_id)
        attrs = normalized_attributes(attributes)
        validate_parent!(location, attrs[:parent_cash_location_id]) if attrs.key?(:parent_cash_location_id)
        location.update!(attrs)
        location
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ActiveRecord::RecordNotUnique => e
        raise InvalidRequest, e.message
      end

      def self.normalized_attributes(attributes)
        attrs = attributes.to_h.symbolize_keys
        attrs[:responsible_operator_id] = attrs[:responsible_operator_id].presence if attrs.key?(:responsible_operator_id)
        attrs[:parent_cash_location_id] = attrs[:parent_cash_location_id].presence if attrs.key?(:parent_cash_location_id)
        attrs[:drawer_code] = attrs[:drawer_code].presence if attrs.key?(:drawer_code)
        attrs[:balancing_required] = ActiveModel::Type::Boolean.new.cast(attrs[:balancing_required]) if attrs.key?(:balancing_required)
        attrs.slice(
          :name,
          :status,
          :responsible_operator_id,
          :parent_cash_location_id,
          :drawer_code,
          :balancing_required,
          :external_reference
        )
      end
      private_class_method :normalized_attributes

      def self.validate_parent!(location, parent_id)
        return if parent_id.blank?
        raise InvalidRequest, "parent cash location cannot reference itself" if parent_id.to_i == location.id

        parent = Models::CashLocation.find(parent_id)
        unless parent.operating_unit_id == location.operating_unit_id
          raise InvalidRequest, "parent cash location must be in the same operating unit"
        end
      end
      private_class_method :validate_parent!
    end
  end
end
