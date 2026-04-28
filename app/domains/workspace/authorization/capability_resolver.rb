# frozen_string_literal: true

module Workspace
  module Authorization
    module CapabilityResolver
      def self.capabilities_for(operator:, scope: nil)
        return [] if operator.nil? || !operator.active?

        Models::Capability
          .joins(roles: :operator_role_assignments)
          .where(active: true)
          .where(roles: { active: true })
          .where(operator_role_assignments: {
            operator_id: operator.id,
            active: true,
            scope_type: nil,
            scope_id: nil
          })
          .where("operator_role_assignments.starts_at IS NULL OR operator_role_assignments.starts_at <= ?", Time.current)
          .where("operator_role_assignments.ends_at IS NULL OR ? < operator_role_assignments.ends_at", Time.current)
          .distinct
          .order(:code)
          .pluck(:code)
      end

      def self.has_capability?(operator:, capability_code:, scope: nil)
        return false if capability_code.blank?

        capabilities_for(operator: operator, scope: scope).include?(capability_code.to_s)
      end
    end
  end
end
