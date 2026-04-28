# frozen_string_literal: true

require "test_helper"

module Organization
  module Models
    class OperatingUnitTest < ActiveSupport::TestCase
      setup do
        BankCore::Seeds::OperatingUnits.seed!
      end

      test "seeded default branch belongs to seeded institution" do
        institution = Services::DefaultOperatingUnit.institution
        branch = Services::DefaultOperatingUnit.branch!

        assert_equal "BANKCORE", institution.code
        assert_equal "institution", institution.unit_type
        assert_equal "MAIN", branch.code
        assert_equal institution.id, branch.parent_operating_unit_id
      end

      test "closed operating units require closed_on" do
        unit = OperatingUnit.new(
          code: "CLOSED-#{SecureRandom.hex(4)}",
          name: "Closed Branch",
          unit_type: "branch",
          status: "closed",
          time_zone: "Eastern Time (US & Canada)"
        )

        assert_not unit.valid?
        assert_includes unit.errors[:closed_on], "is required when status is closed"
      end
    end
  end
end
