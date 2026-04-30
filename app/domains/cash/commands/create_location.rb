# frozen_string_literal: true

module Cash
  module Commands
    class CreateLocation
      class Error < StandardError; end
      class InvalidRequest < Error; end

      def self.call(location_type:, operating_unit: nil, operating_unit_id: nil, actor_id: nil, responsible_operator_id: nil,
        drawer_code: nil, name: nil, parent_cash_location_id: nil, currency: "USD", balancing_required: true,
        external_reference: nil)
        actor = Workspace::Models::Operator.find_by(id: actor_id) if actor_id.present?
        operating_unit ||= Organization::Services::ResolveOperatingUnit.call(
          operator: actor,
          operating_unit_id: operating_unit_id
        )
        authorize_actor!(actor, location_type, operating_unit) if actor.present?

        if actor_id.present? && responsible_operator_id.blank?
          responsible_operator_id = actor_id if location_type.to_s == Cash::Models::CashLocation::TYPE_TELLER_DRAWER
        end

        Cash::Models::CashLocation.transaction do
          existing = find_existing_active(location_type, operating_unit.id, drawer_code)
          return existing if existing

          location = Cash::Models::CashLocation.create!(
            location_type: location_type,
            operating_unit: operating_unit,
            responsible_operator_id: responsible_operator_id,
            parent_cash_location_id: parent_cash_location_id,
            drawer_code: drawer_code.presence,
            name: name.presence || default_name(location_type, drawer_code),
            currency: currency,
            balancing_required: balancing_required,
            external_reference: external_reference
          )
          Cash::Models::CashBalance.create!(cash_location: location, currency: currency, amount_minor_units: 0)
          location
        end
      rescue ActiveRecord::RecordInvalid => e
        raise InvalidRequest, e.record.errors.full_messages.to_sentence
      rescue Workspace::Authorization::Forbidden => e
        raise InvalidRequest, e.message
      end

      def self.authorize_actor!(actor, location_type, operating_unit)
        capabilities = Workspace::Authorization::CapabilityResolver.capabilities_for(
          operator: actor,
          scope: operating_unit
        )
        required = if location_type.to_s == Cash::Models::CashLocation::TYPE_TELLER_DRAWER
          [
            Workspace::Authorization::CapabilityRegistry::CASH_LOCATION_MANAGE,
            Workspace::Authorization::CapabilityRegistry::CASH_DRAWER_MANAGE,
            Workspace::Authorization::CapabilityRegistry::SYSTEM_CONFIGURE
          ]
        else
          [
            Workspace::Authorization::CapabilityRegistry::CASH_LOCATION_MANAGE,
            Workspace::Authorization::CapabilityRegistry::SYSTEM_CONFIGURE
          ]
        end
        return if (capabilities & required).any?

        raise Workspace::Authorization::Forbidden, "operator is not authorized for #{required.join(' or ')}"
      end
      private_class_method :authorize_actor!

      def self.find_existing_active(location_type, operating_unit_id, drawer_code)
        scope = Cash::Models::CashLocation.active.where(
          location_type: location_type,
          operating_unit_id: operating_unit_id
        )
        if location_type.to_s == Cash::Models::CashLocation::TYPE_TELLER_DRAWER
          scope.find_by(drawer_code: drawer_code.presence)
        elsif location_type.to_s == Cash::Models::CashLocation::TYPE_BRANCH_VAULT
          scope.first
        end
      end
      private_class_method :find_existing_active

      def self.default_name(location_type, drawer_code)
        case location_type.to_s
        when Cash::Models::CashLocation::TYPE_BRANCH_VAULT
          "Branch vault"
        when Cash::Models::CashLocation::TYPE_TELLER_DRAWER
          drawer_code.present? ? "Teller drawer #{drawer_code}" : "Teller drawer"
        when Cash::Models::CashLocation::TYPE_INTERNAL_TRANSIT
          "Internal transit"
        else
          raise InvalidRequest, "unsupported location_type"
        end
      end
      private_class_method :default_name
    end
  end
end
