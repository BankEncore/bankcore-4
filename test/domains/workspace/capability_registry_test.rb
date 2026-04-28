# frozen_string_literal: true

require "test_helper"
require "set"

module Workspace
  module Authorization
    class CapabilityRegistryTest < ActiveSupport::TestCase
      test "baseline capability codes are unique" do
        codes = CapabilityRegistry.capability_codes

        assert_equal codes.size, codes.uniq.size
      end

      test "baseline role codes are unique" do
        codes = CapabilityRegistry.role_codes

        assert_equal codes.size, codes.uniq.size
      end

      test "every role capability points to a registered capability" do
        registered = CapabilityRegistry.capability_codes.to_set

        CapabilityRegistry.role_capability_pairs.each do |pair|
          assert_includes registered, pair.fetch(:capability_code)
        end
      end

      test "every registry capability is present in database seed rows" do
        BankCore::Seeds::Rbac.seed!

        persisted_codes = Workspace::Models::Capability.pluck(:code).to_set

        CapabilityRegistry.capability_codes.each do |code|
          assert_includes persisted_codes, code
        end
      end

      test "system admin does not receive financial approval capabilities" do
        financial_codes = [
          CapabilityRegistry::FEE_WAIVE,
          CapabilityRegistry::HOLD_RELEASE,
          CapabilityRegistry::REVERSAL_CREATE,
          CapabilityRegistry::BUSINESS_DATE_CLOSE,
          CapabilityRegistry::TELLER_SESSION_VARIANCE_APPROVE
        ]

        system_admin_codes = CapabilityRegistry::ROLE_CAPABILITIES.fetch(CapabilityRegistry::SYSTEM_ADMIN)

        financial_codes.each do |code|
          assert_not_includes system_admin_codes, code
        end
      end
    end
  end
end
