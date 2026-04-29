# frozen_string_literal: true

module Workspace
  module Commands
    class UpdateOperatorRoleAssignment
      class InvalidRequest < StandardError; end

      def self.call(assignment_id:, attributes:)
        assignment = Models::OperatorRoleAssignment.find(assignment_id)
        attrs = attributes.to_h.symbolize_keys
        scope_id = attrs[:scope_id].presence
        scope_type = scope_id.present? ? attrs[:scope_type].presence : nil
        assignment.update!(
          role_id: attrs[:role_id],
          scope_type: scope_type,
          scope_id: scope_id,
          active: ActiveModel::Type::Boolean.new.cast(attrs.fetch(:active, true)),
          starts_at: parse_time(attrs[:starts_at]),
          ends_at: parse_time(attrs[:ends_at])
        )
        assignment
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ActiveRecord::RecordNotUnique => e
        raise InvalidRequest, e.message
      end

      def self.parse_time(value)
        return nil if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError, TypeError
        raise InvalidRequest, "Time windows must be valid date/time values"
      end
      private_class_method :parse_time
    end
  end
end
