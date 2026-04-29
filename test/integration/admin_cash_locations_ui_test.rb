# frozen_string_literal: true

require "test_helper"

class AdminCashLocationsUiTest < ActionDispatch::IntegrationTest
  setup do
    @admin = create_operator_with_credential!(role: "admin", username: "admin-cash-locations")
    @operating_unit = Organization::Services::DefaultOperatingUnit.branch!
  end

  test "admin can list create edit and deactivate cash locations" do
    internal_login!(username: "admin-cash-locations")

    get "/admin/cash_locations"
    assert_response :success
    assert_includes response.body, "Cash locations"

    get "/admin/cash_locations/new"
    assert_response :success
    assert_includes response.body, "New cash location"
    assert_includes response.body, 'name="cash_location[name]"'

    assert_difference -> { Cash::Models::CashLocation.count }, 1 do
      post "/admin/cash_locations",
        params: {
          cash_location: {
            name: "Admin Transit",
            location_type: "internal_transit",
            operating_unit_id: @operating_unit.id,
            status: "active",
            currency: "USD",
            balancing_required: "1",
            external_reference: "admin-transit"
          }
        }
    end
    location = Cash::Models::CashLocation.order(:id).last
    assert_redirected_to "/admin/cash_locations/#{location.id}"
    assert_equal "Admin Transit", location.name
    assert_equal 0, location.cash_balance.amount_minor_units

    get "/admin/cash_locations/#{location.id}/edit"
    assert_response :success
    assert_includes response.body, "Edit cash location"
    assert_includes response.body, 'name="cash_location[name]"'

    patch "/admin/cash_locations/#{location.id}",
      params: {
        cash_location: {
          name: "Updated Transit",
          status: "active",
          drawer_code: "",
          balancing_required: "0",
          external_reference: "updated-transit"
        }
      }
    assert_redirected_to "/admin/cash_locations/#{location.id}"
    assert_equal "Updated Transit", location.reload.name
    assert_not location.balancing_required?

    post "/admin/cash_locations/#{location.id}/deactivate"
    assert_redirected_to "/admin/cash_locations/#{location.id}"
    assert_equal "inactive", location.reload.status
  end

  test "cash location admin pages are forbidden to non-admin users" do
    create_operator_with_credential!(role: "supervisor", username: "cash-location-non-admin")
    internal_login!(username: "cash-location-non-admin")

    get "/admin/cash_locations"
    assert_response :forbidden
  end
end
