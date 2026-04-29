# frozen_string_literal: true

module BankCore
  module Seeds
    module CashInventory
      INTERNAL_TRANSIT_REFERENCE = "seed:main-internal-transit"
      DEV_DRAWER_CODE = "DEV-1"

      def self.seed!
        branch = Organization::Services::DefaultOperatingUnit.branch!

        branch_vault(branch)
        internal_transit(branch)
        development_drawer(branch) if Rails.env.development? || Rails.env.test?
      end

      def self.branch_vault(branch)
        Cash::Commands::CreateLocation.call(
          location_type: Cash::Models::CashLocation::TYPE_BRANCH_VAULT,
          operating_unit: branch,
          name: "Main Branch Vault",
          currency: "USD",
          balancing_required: true,
          external_reference: "seed:main-branch-vault"
        )
      end
      private_class_method :branch_vault

      def self.internal_transit(branch)
        existing = Cash::Models::CashLocation.active.find_by(
          operating_unit: branch,
          location_type: Cash::Models::CashLocation::TYPE_INTERNAL_TRANSIT,
          external_reference: INTERNAL_TRANSIT_REFERENCE
        )
        return existing if existing

        Cash::Commands::CreateLocation.call(
          location_type: Cash::Models::CashLocation::TYPE_INTERNAL_TRANSIT,
          operating_unit: branch,
          name: "Main Branch Internal Transit",
          currency: "USD",
          balancing_required: true,
          external_reference: INTERNAL_TRANSIT_REFERENCE
        )
      end
      private_class_method :internal_transit

      def self.development_drawer(branch)
        Cash::Commands::CreateLocation.call(
          location_type: Cash::Models::CashLocation::TYPE_TELLER_DRAWER,
          operating_unit: branch,
          drawer_code: DEV_DRAWER_CODE,
          name: "Development Teller Drawer #{DEV_DRAWER_CODE}",
          currency: "USD",
          balancing_required: true,
          external_reference: "seed:dev-teller-drawer"
        )
      end
      private_class_method :development_drawer
    end
  end
end
