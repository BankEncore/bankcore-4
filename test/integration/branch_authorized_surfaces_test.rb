# frozen_string_literal: true

require "test_helper"

class BranchAuthorizedSurfacesTest < ActionDispatch::IntegrationTest
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 8, 1))
    @teller = create_operator_with_credential!(role: "teller", username: "branch-surf-teller")
    @supervisor = create_operator_with_credential!(role: "supervisor", username: "branch-surf-supervisor")
    @saved_threshold = Rails.application.config.x.teller.variance_threshold_minor_units
    Rails.application.config.x.teller.variance_threshold_minor_units = 0
  end

  teardown do
    Rails.application.config.x.teller.variance_threshold_minor_units = @saved_threshold
  end

  test "branch dashboard exposes surface anchors and supervisor can approve variance via HTML" do
    internal_login!(username: "branch-surf-teller")
    get "/branch/teller_sessions/new"
    assert_response :success
    post "/branch/teller_sessions", params: { teller_session: { drawer_code: "surf-drawer" } }
    assert_redirected_to "/branch"
    sid = Teller::Models::TellerSession.order(:id).last.id

    post "/branch/teller_sessions/#{sid}/close", params: { teller_session_close: { actual_cash_minor_units: 50_000 } }
    assert_redirected_to "/branch#supervisor"
    session = Teller::Models::TellerSession.find(sid)
    assert_equal "pending_supervisor", session.status

    delete "/logout"

    internal_login!(username: "branch-surf-supervisor")
    get "/branch"
    assert_response :success
    assert_includes response.body, 'id="csr"'
    assert_includes response.body, 'id="teller"'
    assert_includes response.body, 'id="supervisor"'
    assert_includes response.body, "Approve variance"

    assert_difference -> { Teller::Models::TellerSession.where(status: "closed").count }, 1 do
      post "/branch/teller_sessions/approve_variance",
        params: { teller_session_approve_variance: { teller_session_id: sid } }
    end
    assert_response :redirect
    assert_match %r{/branch#supervisor\z}, response.redirect_url
    assert_equal "closed", Teller::Models::TellerSession.find(sid).status
  end

  test "teller cannot approve session variance via branch HTML" do
    internal_login!(username: "branch-surf-teller")
    post "/branch/teller_sessions", params: { teller_session: { drawer_code: "surf-d2" } }
    sid = Teller::Models::TellerSession.order(:id).last.id
    post "/branch/teller_sessions/#{sid}/close", params: { teller_session_close: { actual_cash_minor_units: 25_000 } }

    post "/branch/teller_sessions/approve_variance",
      params: { teller_session_approve_variance: { teller_session_id: sid } }
    assert_redirected_to "/branch#supervisor"
    assert_match(/inline supervisor credentials are invalid/i, flash[:alert].to_s)
    assert_equal "pending_supervisor", Teller::Models::TellerSession.find(sid).status
  end

  test "teller can approve session variance with inline supervisor credentials" do
    internal_login!(username: "branch-surf-teller")
    post "/branch/teller_sessions", params: { teller_session: { drawer_code: "surf-inline" } }
    sid = Teller::Models::TellerSession.order(:id).last.id
    post "/branch/teller_sessions/#{sid}/close", params: { teller_session_close: { actual_cash_minor_units: 25_000 } }

    get "/branch"
    assert_response :success
    assert_includes response.body, "Inline supervisor approval"

    post "/branch/teller_sessions/approve_variance",
      params: {
        teller_session_approve_variance: {
          teller_session_id: sid,
          supervisor_username: "branch-surf-supervisor",
          supervisor_password: "password123"
        }
      }

    assert_redirected_to "/branch#supervisor"
    session = Teller::Models::TellerSession.find(sid)
    assert_equal "closed", session.status
    assert_equal @supervisor.id, session.supervisor_operator_id
  end

  test "branch override approved requires override approve capability not only teller role" do
    internal_login!(username: "branch-surf-teller")
    post "/branch/overrides",
      params: {
        override: {
          event_type: "override.approved",
          reference_id: "teller_session:1",
          idempotency_key: "branch-ovr-#{SecureRandom.hex(4)}"
        }
      }
    assert_redirected_to "/branch"
    assert_match(/Override approval capability required/i, flash[:alert].to_s)
  end
end
