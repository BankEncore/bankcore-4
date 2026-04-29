# frozen_string_literal: true

require "test_helper"

class TellerCashInventoryJsonTest < ActionDispatch::IntegrationTest
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 29))
    @teller, @supervisor = create_workspace_operators!
  end

  test "cash position includes drawer created by teller session" do
    post "/teller/teller_sessions", params: { drawer_code: "JSON1" }.to_json, headers: teller_json_headers(@teller)
    assert_response :created
    cash_location_id = response.parsed_body.fetch("cash_location_id")

    get "/teller/cash/position", headers: teller_json_headers(@teller)
    assert_response :success
    ids = response.parsed_body.fetch("locations").map { |row| row.fetch("id") }
    assert_includes ids, cash_location_id
  end

  test "supervisor can create branch vault and teller can record count" do
    post "/teller/cash/locations",
      params: { cash_location: { location_type: "branch_vault", name: "Main vault" } }.to_json,
      headers: teller_json_headers(@supervisor)
    assert_response :created
    vault_id = response.parsed_body.fetch("id")

    post "/teller/cash/counts",
      params: {
        cash_count: {
          cash_location_id: vault_id,
          counted_amount_minor_units: 50_000,
          expected_amount_minor_units: 0,
          idempotency_key: "json-vault-count"
        }
      }.to_json,
      headers: teller_json_headers(@teller)
    assert_response :created
    assert_equal vault_id, response.parsed_body.fetch("cash_location_id")
    assert_predicate response.parsed_body.fetch("cash_variance_id"), :present?
  end
end
