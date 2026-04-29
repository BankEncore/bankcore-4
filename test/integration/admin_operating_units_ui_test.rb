# frozen_string_literal: true

require "test_helper"

class AdminOperatingUnitsUiTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_operator_with_credential!(role: "admin", username: "admin-ou")
    @institution = Organization::Services::DefaultOperatingUnit.institution
  end

  test "admin can list create edit and close operating units" do
    internal_login!(username: "admin-ou")

    get "/admin/operating_units"
    assert_response :success
    assert_includes response.body, "Operating units"

    get "/admin/operating_units/new"
    assert_response :success
    assert_includes response.body, "New operating unit"
    assert_includes response.body, 'name="operating_unit[code]"'

    assert_difference -> { Organization::Models::OperatingUnit.count }, 1 do
      post "/admin/operating_units",
        params: {
          operating_unit: {
            code: "adm-ou-#{SecureRandom.hex(4)}",
            name: "Admin Managed Unit",
            unit_type: "department",
            status: "active",
            parent_operating_unit_id: @institution.id,
            time_zone: "Eastern Time (US & Canada)",
            opened_on: "2026-04-29"
          }
        }
    end
    unit = Organization::Models::OperatingUnit.order(:id).last
    assert_redirected_to "/admin/operating_units/#{unit.id}"
    assert_equal "Admin Managed Unit", unit.name

    get "/admin/operating_units/#{unit.id}/edit"
    assert_response :success
    assert_includes response.body, "Edit operating unit"
    assert_includes response.body, 'name="operating_unit[name]"'

    patch "/admin/operating_units/#{unit.id}",
      params: {
        operating_unit: {
          code: unit.code,
          name: "Updated Admin Unit",
          unit_type: "department",
          status: "inactive",
          parent_operating_unit_id: @institution.id,
          time_zone: "Central Time (US & Canada)"
        }
      }
    assert_redirected_to "/admin/operating_units/#{unit.id}"
    assert_equal "Updated Admin Unit", unit.reload.name
    assert_equal "inactive", unit.status

    post "/admin/operating_units/#{unit.id}/close",
      params: { operating_unit: { closed_on: "2026-04-30" } }
    assert_redirected_to "/admin/operating_units/#{unit.id}"
    assert_equal "closed", unit.reload.status
    assert_equal Date.new(2026, 4, 30), unit.closed_on
  end

  test "operating unit admin pages are forbidden to non-admin users" do
    create_operator_with_credential!(role: "supervisor", username: "ou-non-admin")
    internal_login!(username: "ou-non-admin")

    get "/admin/operating_units"
    assert_response :forbidden
  end
end
