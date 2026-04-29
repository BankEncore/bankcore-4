# frozen_string_literal: true

module Workspace
  module Commands
    class AssignOperatorRole
      class InvalidRequest < StandardError; end

      def self.call(attributes:)
        attrs = attributes.to_h.symbolize_keys
        assignment_attrs = normalized_assignment_attrs(attrs)
        finder = assignment_attrs.slice(:operator_id, :role_id, :scope_type, :scope_id)

        assignment = Models::OperatorRoleAssignment.find_or_initialize_by(finder)
        assignment.assign_attributes(assignment_attrs.slice(:active, :starts_at, :ends_at))
        assignment.save!
        assignment
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound, ActiveRecord::RecordNotUnique => e
        raise InvalidRequest, e.message
      end

      def self.normalized_assignment_attrs(attrs)
        scope_type = attrs[:scope_type].presence
        scope_id = attrs[:scope_id].presence
        scope_type = nil if scope_id.blank?

        {
          operator_id: attrs.fetch(:operator_id),
          role_id: attrs.fetch(:role_id),
          scope_type: scope_type,
          scope_id: scope_id,
          active: ActiveModel::Type::Boolean.new.cast(attrs.fetch(:active, true)),
          starts_at: parse_time(attrs[:starts_at]),
          ends_at: parse_time(attrs[:ends_at])
        }
      end
      private_class_method :normalized_assignment_attrs

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
