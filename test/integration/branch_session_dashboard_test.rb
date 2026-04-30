# frozen_string_literal: true

require "test_helper"

class BranchSessionDashboardTest < ActionDispatch::IntegrationTest
  setup do
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 24))
  end

  test "teller can view branch session dashboard with grouped sessions" do
    create_operator_with_credential!(role: "teller", username: "branch-dashboard")
    open_session = create_session!(
      status: "open",
      drawer_code: "drawer-open",
      opened_at: Time.zone.parse("2026-04-24 09:00")
    )
    pending_session = create_session!(
      status: "pending_supervisor",
      drawer_code: "drawer-pending",
      opened_at: Time.zone.parse("2026-04-24 08:00"),
      expected_cash_minor_units: 10_000,
      actual_cash_minor_units: 11_250,
      variance_minor_units: 1_250
    )
    closed_session = create_session!(
      status: "closed",
      drawer_code: "drawer-closed",
      opened_at: Time.zone.parse("2026-04-24 07:00"),
      closed_at: Time.zone.parse("2026-04-24 12:00"),
      expected_cash_minor_units: 5_000,
      actual_cash_minor_units: 4_750,
      variance_minor_units: -250
    )

    internal_login!(username: "branch-dashboard")
    get "/branch"

    assert_response :success
    assert_select "h1", "Branch workspace"
    assert_includes response.body, 'id="csr"'
    assert_match(/customer servicing/i, response.body)
    assert_includes response.body, "##{open_session.id}"
    assert_includes response.body, "##{pending_session.id}"
    assert_includes response.body, "##{closed_session.id}"
    assert_includes response.body, "drawer-open"
    assert_includes response.body, "drawer-pending"
    assert_includes response.body, "drawer-closed"
    assert_includes response.body, "Variance is calculated as actual cash minus expected cash at close."
    assert_includes response.body, "Approval required"
    assert_includes response.body, "+$12.50"
    assert_includes response.body, "-$2.50"
  end

  test "closing with variance redirects to supervisor evidence" do
    create_operator_with_credential!(role: "teller", username: "branch-close-variance")
    session = create_session!(
      status: "open",
      drawer_code: "drawer-variance",
      opened_at: Time.zone.parse("2026-04-24 09:00")
    )

    internal_login!(username: "branch-close-variance")
    post close_branch_teller_session_path(session), params: {
      teller_session_close: { actual_cash_minor_units: 125 }
    }

    assert_redirected_to "#{branch_path}#supervisor"
    assert_equal Teller::Models::TellerSession::STATUS_PENDING_SUPERVISOR, session.reload.status
    assert_equal 0, session.expected_cash_minor_units
    assert_equal 125, session.actual_cash_minor_units
    assert_equal 125, session.variance_minor_units
  end

  test "branch dashboard renders empty states" do
    create_operator_with_credential!(role: "supervisor", username: "empty-branch-dashboard")

    internal_login!(username: "empty-branch-dashboard")
    get "/branch"

    assert_response :success
    assert_includes response.body, "No open teller sessions."
    assert_includes response.body, "No sessions are waiting for supervisor variance approval."
    assert_includes response.body, "No closed teller sessions yet."
  end

  test "operations and admin users remain forbidden from branch dashboard" do
    create_operator_with_credential!(role: "operations", username: "ops-no-branch")
    internal_login!(username: "ops-no-branch")

    get "/branch"
    assert_response :forbidden

    delete "/logout"
    create_operator_with_credential!(role: "admin", username: "admin-no-branch")
    internal_login!(username: "admin-no-branch")

    get "/branch"
    assert_response :forbidden
  end

  private

  def create_session!(**attrs)
    Teller::Models::TellerSession.create!(
      {
        status: attrs.fetch(:status),
        opened_at: attrs.fetch(:opened_at),
        drawer_code: attrs.fetch(:drawer_code),
        expected_cash_minor_units: attrs[:expected_cash_minor_units],
        actual_cash_minor_units: attrs[:actual_cash_minor_units],
        variance_minor_units: attrs[:variance_minor_units],
        closed_at: attrs[:closed_at]
      }
    )
  end
end
