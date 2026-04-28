# frozen_string_literal: true

require "test_helper"

module Workspace
  module Authorization
    class CapabilityResolverTest < ActiveSupport::TestCase
      setup do
        BankCore::Seeds::Rbac.seed!
      end

      test "backfill creates expected assignment from legacy operator role" do
        operator = Models::Operator.create!(role: "supervisor", display_name: "RBAC Supervisor", active: true)
        operator.operator_role_assignments.delete_all

        BankCore::Seeds::Rbac.seed!

        assignment = operator.operator_role_assignments.joins(:role).find_by!(roles: { code: CapabilityRegistry::BRANCH_SUPERVISOR })
        assert assignment.active?
        assert_nil assignment.scope_type
        assert_nil assignment.scope_id
      end

      test "operator capabilities come from active global assignments" do
        operator = Models::Operator.create!(role: "supervisor", display_name: "RBAC Supervisor", active: true)

        assert operator.has_capability?(CapabilityRegistry::REVERSAL_CREATE)
        assert operator.has_capability?(CapabilityRegistry::FEE_WAIVE)
      end

      test "inactive operators receive no capabilities" do
        operator = Models::Operator.create!(role: "supervisor", display_name: "Inactive Supervisor", active: false)

        assert_empty CapabilityResolver.capabilities_for(operator: operator)
        assert_not operator.has_capability?(CapabilityRegistry::REVERSAL_CREATE)
      end

      test "inactive role assignment grants no capabilities" do
        operator = Models::Operator.create!(role: "supervisor", display_name: "Inactive Assignment Supervisor", active: true)
        operator.operator_role_assignments.update_all(active: false)

        assert_not operator.has_capability?(CapabilityRegistry::REVERSAL_CREATE)
      end

      test "inactive role grants no capabilities" do
        operator = Models::Operator.create!(role: "supervisor", display_name: "Inactive Role Supervisor", active: true)
        role = Models::Role.find_by!(code: CapabilityRegistry::BRANCH_SUPERVISOR)

        role.update!(active: false)
        assert_not operator.has_capability?(CapabilityRegistry::REVERSAL_CREATE)
      ensure
        role&.update!(active: true)
      end

      test "inactive capability grants nothing" do
        operator = Models::Operator.create!(role: "supervisor", display_name: "Inactive Capability Supervisor", active: true)
        capability = Models::Capability.find_by!(code: CapabilityRegistry::REVERSAL_CREATE)

        capability.update!(active: false)
        assert_not operator.has_capability?(CapabilityRegistry::REVERSAL_CREATE)
      ensure
        capability&.update!(active: true)
      end

      test "future assignment grants no capabilities until starts_at" do
        operator = Models::Operator.create!(role: "supervisor", display_name: "Future Supervisor", active: true)
        operator.operator_role_assignments.update_all(starts_at: 1.hour.from_now)

        assert_not operator.has_capability?(CapabilityRegistry::REVERSAL_CREATE)
      end

      test "expired assignment grants no capabilities at exclusive ends_at" do
        operator = Models::Operator.create!(role: "supervisor", display_name: "Expired Supervisor", active: true)
        operator.operator_role_assignments.update_all(ends_at: Time.current)

        assert_not operator.has_capability?(CapabilityRegistry::REVERSAL_CREATE)
      end

      test "scope argument still resolves global capabilities only" do
        operator = Models::Operator.create!(role: "teller", display_name: "Scoped Teller", active: true)

        assert operator.has_capability?(CapabilityRegistry::DEPOSIT_ACCEPT, scope: { branch_id: 1 })
      end

      test "scoped assignment rows grant nothing until scoped RBAC exists" do
        operator = Models::Operator.create!(role: "teller", display_name: "Scoped Assignment Teller", active: true)
        auditor = Models::Role.find_by!(code: CapabilityRegistry::AUDITOR)
        Models::OperatorRoleAssignment.create!(
          operator: operator,
          role: auditor,
          scope_type: "branch",
          scope_id: 1,
          active: true
        )

        assert_not operator.has_capability?(CapabilityRegistry::JOURNAL_ENTRY_VIEW, scope: { branch_id: 1 })
      end

      test "unknown capability fails closed" do
        operator = Models::Operator.create!(role: "supervisor", display_name: "Unknown Capability Supervisor", active: true)

        assert_not operator.has_capability?("not.real")
      end
    end
  end
end
