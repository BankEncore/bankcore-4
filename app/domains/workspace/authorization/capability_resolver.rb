# frozen_string_literal: true

module Workspace
  module Authorization
    module CapabilityResolver
      def self.capabilities_for(operator:, scope: nil)
        return [] if operator.nil? || !operator.active?

        assignments = {
          operator_id: operator.id,
          active: true
        }
        assignment_scope = scope_conditions_for(scope)

        query = Models::Capability
          .joins(roles: :operator_role_assignments)
          .where(active: true)
          .where(roles: { active: true })
          .where(operator_role_assignments: assignments)
          .where("operator_role_assignments.starts_at IS NULL OR operator_role_assignments.starts_at <= ?", Time.current)
          .where("operator_role_assignments.ends_at IS NULL OR ? < operator_role_assignments.ends_at", Time.current)

        query = if assignment_scope.nil?
          query.where(operator_role_assignments: { scope_type: nil, scope_id: nil })
        else
          query.where(
            "(operator_role_assignments.scope_type IS NULL AND operator_role_assignments.scope_id IS NULL) OR " \
              "(operator_role_assignments.scope_type = :scope_type AND operator_role_assignments.scope_id = :scope_id)",
            scope_type: assignment_scope.fetch(:scope_type),
            scope_id: assignment_scope.fetch(:scope_id)
          )
        end

        query
          .distinct
          .order(:code)
          .pluck(:code)
      end

      def self.has_capability?(operator:, capability_code:, scope: nil)
        return false if capability_code.blank?

        capabilities_for(operator: operator, scope: scope).include?(capability_code.to_s)
      end

      def self.scope_conditions_for(scope)
        return nil if scope.blank?

        if scope.is_a?(Organization::Models::OperatingUnit)
          return { scope_type: "operating_unit", scope_id: scope.id }
        end

        if scope.respond_to?(:to_h)
          scope_hash = scope.to_h.with_indifferent_access
          scope_id = scope_hash[:operating_unit_id] || scope_hash[:scope_id]
          scope_type = scope_hash[:scope_type] || "operating_unit"
          return nil if scope_id.blank?
          return { scope_type: scope_type.to_s, scope_id: scope_id.to_i } if scope_type.to_s == "operating_unit"
        end

        nil
      end
      private_class_method :scope_conditions_for
    end
  end
end
