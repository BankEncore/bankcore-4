# frozen_string_literal: true

require "test_helper"

module Organization
  class AdminOperatingUnitCommandsTest < ActiveSupport::TestCase
    setup do
      BankCore::Seeds::OperatingUnits.seed!
      @institution = Services::DefaultOperatingUnit.institution
    end

    test "creates and updates an operating unit" do
      unit = Commands::CreateOperatingUnit.call(
        attributes: {
          code: "ops-#{SecureRandom.hex(4)}",
          name: "Ops Center",
          unit_type: "operations",
          status: "active",
          parent_operating_unit_id: @institution.id,
          time_zone: "Eastern Time (US & Canada)",
          opened_on: "2026-04-29"
        }
      )

      assert_equal "OPS", unit.code.first(3)
      assert_equal @institution.id, unit.parent_operating_unit_id

      Commands::UpdateOperatingUnit.call(
        operating_unit_id: unit.id,
        attributes: {
          name: "Updated Ops Center",
          status: "inactive",
          time_zone: "Central Time (US & Canada)"
        }
      )

      assert_equal "Updated Ops Center", unit.reload.name
      assert_equal "inactive", unit.status
      assert_equal "Central Time (US & Canada)", unit.time_zone
    end

    test "protects seeded default operating unit codes" do
      branch = Services::DefaultOperatingUnit.branch!

      error = assert_raises(Commands::UpdateOperatingUnit::InvalidRequest) do
        Commands::UpdateOperatingUnit.call(
          operating_unit_id: branch.id,
          attributes: { code: "RENAMED", name: branch.name }
        )
      end

      assert_match(/cannot be changed/, error.message)
      assert_equal "MAIN", branch.reload.code
    end

    test "prevents parent cycles" do
      parent = create_unit!("PARENT")
      child = create_unit!("CHILD", parent: parent)

      error = assert_raises(Commands::UpdateOperatingUnit::InvalidRequest) do
        Commands::UpdateOperatingUnit.call(
          operating_unit_id: parent.id,
          attributes: { parent_operating_unit_id: child.id }
        )
      end

      assert_match(/descendant/, error.message)
    end

    test "closes operating unit only after active children and cash locations are cleared" do
      unit = create_unit!("CLOSE")
      create_unit!("ACTIVECHILD", parent: unit)

      error = assert_raises(Commands::CloseOperatingUnit::InvalidRequest) do
        Commands::CloseOperatingUnit.call(operating_unit_id: unit.id, closed_on: "2026-04-29")
      end
      assert_match(/active child/, error.message)

      unit.child_operating_units.update_all(status: "inactive")
      Cash::Commands::CreateLocation.call(
        location_type: Cash::Models::CashLocation::TYPE_BRANCH_VAULT,
        operating_unit: unit,
        name: "Close Unit Vault"
      )

      error = assert_raises(Commands::CloseOperatingUnit::InvalidRequest) do
        Commands::CloseOperatingUnit.call(operating_unit_id: unit.id, closed_on: "2026-04-29")
      end
      assert_match(/active cash locations/, error.message)

      Cash::Models::CashLocation.where(operating_unit: unit).update_all(status: "inactive")
      Commands::CloseOperatingUnit.call(operating_unit_id: unit.id, closed_on: "2026-04-29")

      assert_equal "closed", unit.reload.status
      assert_equal Date.new(2026, 4, 29), unit.closed_on
    end

    private

    def create_unit!(code, parent: @institution)
      Models::OperatingUnit.create!(
        code: "#{code}-#{SecureRandom.hex(4)}",
        name: "#{code.titleize} Unit",
        unit_type: "branch",
        parent_operating_unit: parent,
        status: "active",
        time_zone: "Eastern Time (US & Canada)",
        opened_on: Date.current
      )
    end
  end
end
