# frozen_string_literal: true

module BankCore
  module Seeds
    module Rbac
      def self.seed!
        now = Time.current

        Workspace::Authorization::CapabilityRegistry::CAPABILITIES.each do |attrs|
          capability = Workspace::Models::Capability.find_or_initialize_by(code: attrs.fetch(:code))
          capability.assign_attributes(
            name: attrs.fetch(:name),
            description: attrs[:description],
            category: attrs.fetch(:category),
            active: true
          )
          capability.save!
        end

        Workspace::Authorization::CapabilityRegistry::ROLES.each do |attrs|
          role = Workspace::Models::Role.find_or_initialize_by(code: attrs.fetch(:code))
          role.assign_attributes(
            name: attrs.fetch(:name),
            description: attrs[:description],
            active: true,
            system_role: true
          )
          role.save!
        end

        capabilities_by_code = Workspace::Models::Capability.where(
          code: Workspace::Authorization::CapabilityRegistry.capability_codes
        ).index_by(&:code)
        roles_by_code = Workspace::Models::Role.where(
          code: Workspace::Authorization::CapabilityRegistry.role_codes
        ).index_by(&:code)

        Workspace::Authorization::CapabilityRegistry.role_capability_pairs.each do |pair|
          Workspace::Models::RoleCapability.find_or_create_by!(
            role: roles_by_code.fetch(pair.fetch(:role_code)),
            capability: capabilities_by_code.fetch(pair.fetch(:capability_code))
          )
        end

        Workspace::Models::Operator.find_each do |operator|
          role_code = Workspace::Authorization::CapabilityRegistry::LEGACY_ROLE_MAPPING[operator.role]
          next if role_code.blank?

          Workspace::Models::OperatorRoleAssignment.find_or_create_by!(
            operator: operator,
            role: roles_by_code.fetch(role_code),
            scope_type: nil,
            scope_id: nil
          ) do |assignment|
            assignment.active = true
            assignment.starts_at = nil
            assignment.ends_at = nil
            assignment.created_at = now
            assignment.updated_at = now
          end
        end
      end
    end
  end
end
