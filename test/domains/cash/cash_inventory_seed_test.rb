# frozen_string_literal: true

require "test_helper"
require_relative "../../../lib/bank_core/seeds/cash_inventory"

class CashInventorySeedTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::OperatingUnits.seed!
  end

  test "cash inventory seed creates default branch reference locations with zero balances" do
    BankCore::Seeds::CashInventory.seed!

    branch = Organization::Services::DefaultOperatingUnit.branch!
    vault = Cash::Models::CashLocation.find_by!(
      operating_unit: branch,
      location_type: Cash::Models::CashLocation::TYPE_BRANCH_VAULT,
      status: Cash::Models::CashLocation::STATUS_ACTIVE
    )
    transit = Cash::Models::CashLocation.find_by!(
      operating_unit: branch,
      location_type: Cash::Models::CashLocation::TYPE_INTERNAL_TRANSIT,
      external_reference: BankCore::Seeds::CashInventory::INTERNAL_TRANSIT_REFERENCE,
      status: Cash::Models::CashLocation::STATUS_ACTIVE
    )
    drawer = Cash::Models::CashLocation.find_by!(
      operating_unit: branch,
      location_type: Cash::Models::CashLocation::TYPE_TELLER_DRAWER,
      drawer_code: BankCore::Seeds::CashInventory::DEV_DRAWER_CODE,
      status: Cash::Models::CashLocation::STATUS_ACTIVE
    )

    assert_equal 0, vault.cash_balance.amount_minor_units
    assert_equal 0, transit.cash_balance.amount_minor_units
    assert_equal 0, drawer.cash_balance.amount_minor_units
  end

  test "cash inventory seed is idempotent for active default locations" do
    BankCore::Seeds::CashInventory.seed!
    BankCore::Seeds::CashInventory.seed!

    branch = Organization::Services::DefaultOperatingUnit.branch!
    assert_equal 1, Cash::Models::CashLocation.active.where(
      operating_unit: branch,
      location_type: Cash::Models::CashLocation::TYPE_BRANCH_VAULT
    ).count
    assert_equal 1, Cash::Models::CashLocation.active.where(
      operating_unit: branch,
      location_type: Cash::Models::CashLocation::TYPE_INTERNAL_TRANSIT,
      external_reference: BankCore::Seeds::CashInventory::INTERNAL_TRANSIT_REFERENCE
    ).count
    assert_equal 1, Cash::Models::CashLocation.active.where(
      operating_unit: branch,
      location_type: Cash::Models::CashLocation::TYPE_TELLER_DRAWER,
      drawer_code: BankCore::Seeds::CashInventory::DEV_DRAWER_CODE
    ).count
  end

  test "seed chain can create cash reference data after prerequisites" do
    BankCore::Seeds::GlCoa.seed!
    BankCore::Seeds::DepositProducts.seed!
    BankCore::Seeds::OperatingUnits.seed!
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.current) if Core::BusinessDate::Models::BusinessDateSetting.none?
    BankCore::Seeds::Rbac.seed!
    BankCore::Seeds::CashInventory.seed!

    branch = Organization::Services::DefaultOperatingUnit.branch!
    assert Cash::Models::CashLocation.active.where(operating_unit: branch).exists?
  end
end
