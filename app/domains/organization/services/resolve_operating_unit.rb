# frozen_string_literal: true

module Organization
  module Services
    module ResolveOperatingUnit
      class Error < StandardError; end
      class NotAuthorized < Error; end

      def self.call(operator:, teller_session_id: nil, operating_unit_id: nil)
        from_session = operating_unit_from_session(teller_session_id)
        return from_session if from_session.present?

        explicit = operating_unit_from_explicit(operator, operating_unit_id)
        return explicit if explicit.present?

        return operator.default_operating_unit if operator&.default_operating_unit&.active?

        DefaultOperatingUnit.branch!
      end

      def self.operating_unit_from_session(teller_session_id)
        return nil if teller_session_id.blank?

        session = Teller::Models::TellerSession.find_by(id: teller_session_id.to_i)
        session&.operating_unit
      end
      private_class_method :operating_unit_from_session

      def self.operating_unit_from_explicit(operator, operating_unit_id)
        return nil if operating_unit_id.blank?

        unit = Models::OperatingUnit.active.find_by(id: operating_unit_id.to_i)
        raise NotAuthorized, "operating unit not found or inactive" if unit.nil?

        if operator&.capabilities(scope: unit)&.any?
          unit
        else
          raise NotAuthorized, "operator is not authorized for operating unit"
        end
      end
      private_class_method :operating_unit_from_explicit
    end
  end
end
