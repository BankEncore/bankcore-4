# frozen_string_literal: true

module Workspace
  module Models
    class Operator < ApplicationRecord
      self.table_name = "operators"

      ROLES = %w[teller supervisor operations admin].freeze

      has_one :credential, class_name: "Workspace::Models::OperatorCredential", dependent: :destroy
      has_many :operator_role_assignments, class_name: "Workspace::Models::OperatorRoleAssignment", dependent: :destroy
      has_many :roles, through: :operator_role_assignments, class_name: "Workspace::Models::Role"

      validates :role, presence: true, inclusion: { in: ROLES }

      after_create :assign_legacy_compatible_role

      def teller?
        role == "teller"
      end

      def supervisor?
        role == "supervisor"
      end

      def operations?
        role == "operations"
      end

      def admin?
        role == "admin"
      end

      def capabilities(scope: nil)
        Workspace::Authorization::CapabilityResolver.capabilities_for(operator: self, scope: scope)
      end

      def has_capability?(capability_code, scope: nil)
        Workspace::Authorization::CapabilityResolver.has_capability?(
          operator: self,
          capability_code: capability_code,
          scope: scope
        )
      end

      private

      def assign_legacy_compatible_role
        role_code = Workspace::Authorization::CapabilityRegistry::LEGACY_ROLE_MAPPING[role]
        return if role_code.blank?

        role_record = Workspace::Models::Role.find_by(code: role_code)
        return if role_record.nil?

        operator_role_assignments.find_or_create_by!(role: role_record, scope_type: nil, scope_id: nil) do |assignment|
          assignment.active = true
        end
      rescue ActiveRecord::StatementInvalid
        # Operators can be created while RBAC tables are not present during a fresh migration.
        nil
      end
    end
  end
end
