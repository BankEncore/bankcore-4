# frozen_string_literal: true

require "test_helper"

module Workspace
  class AdminRbacCommandsTest < ActiveSupport::TestCase
    setup do
      BankCore::Seeds::Rbac.seed!
      @branch = Organization::Services::DefaultOperatingUnit.branch
    end

    test "creates operator with normalized credential and resets password" do
      operator = Commands::CreateOperator.call(
        attributes: {
          display_name: "RBAC Operator",
          role: "teller",
          active: true,
          default_operating_unit_id: @branch.id,
          username: "  RBAC-User  ",
          password: "password123"
        }
      )

      assert_equal "rbac-user", operator.credential.username
      assert operator.active?

      Commands::ResetOperatorCredential.call(
        operator_id: operator.id,
        username: "RBAC-Reset",
        password: "new-password123"
      )

      credential = operator.reload.credential
      assert_equal "rbac-reset", credential.username
      assert credential.authenticate("new-password123")
      assert_equal 0, credential.failed_login_attempts
      assert_nil credential.locked_at
    end

    test "assigns operating unit scoped role and resolver sees capability" do
      operator = Models::Operator.create!(
        display_name: "Scoped Operator",
        role: "teller",
        active: true,
        default_operating_unit: @branch
      )
      role = Models::Role.find_by!(code: Authorization::CapabilityRegistry::OPERATIONS)

      assignment = Commands::AssignOperatorRole.call(
        attributes: {
          operator_id: operator.id,
          role_id: role.id,
          scope_type: "operating_unit",
          scope_id: @branch.id,
          active: true
        }
      )

      assert_equal "operating_unit", assignment.scope_type
      assert operator.has_capability?(Authorization::CapabilityRegistry::OPS_BATCH_PROCESS, scope: @branch)

      Commands::DeactivateOperatorRoleAssignment.call(assignment_id: assignment.id)
      assert_not operator.has_capability?(Authorization::CapabilityRegistry::OPS_BATCH_PROCESS, scope: @branch)
    end

    test "role capability updates affect runtime authorization" do
      operator = Models::Operator.create!(
        display_name: "Custom Role Operator",
        role: "teller",
        active: true,
        default_operating_unit: @branch
      )
      role = Commands::CreateRole.call(
        attributes: {
          code: "custom_#{SecureRandom.hex(4)}",
          name: "Custom Role",
          active: true
        }
      )
      capability = Models::Capability.find_by!(code: Authorization::CapabilityRegistry::AUDIT_EXPORT)
      Commands::UpdateRoleCapabilities.call(role_id: role.id, capability_ids: [ capability.id ])
      Commands::AssignOperatorRole.call(attributes: { operator_id: operator.id, role_id: role.id, active: true })

      assert operator.has_capability?(Authorization::CapabilityRegistry::AUDIT_EXPORT, scope: @branch)

      Commands::UpdateRoleCapabilities.call(role_id: role.id, capability_ids: [])
      assert_not operator.has_capability?(Authorization::CapabilityRegistry::AUDIT_EXPORT, scope: @branch)
    end

    test "system roles cannot be deactivated" do
      role = Models::Role.find_by!(code: Authorization::CapabilityRegistry::SYSTEM_ADMIN)

      error = assert_raises(Commands::DeactivateRole::InvalidRequest) do
        Commands::DeactivateRole.call(role_id: role.id)
      end

      assert_equal "System roles cannot be deactivated", error.message
      assert role.reload.active?
    end

    test "capabilities are soft deactivated" do
      capability = Commands::CreateCapability.call(
        attributes: {
          code: "custom.capability.#{SecureRandom.hex(4)}",
          name: "Custom Capability",
          category: "admin",
          active: true
        }
      )

      Commands::DeactivateCapability.call(capability_id: capability.id)
      assert_not capability.reload.active?
    end
  end
end
