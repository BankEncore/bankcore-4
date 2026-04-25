# frozen_string_literal: true

require "test_helper"

class InternalAuthTest < ActionDispatch::IntegrationTest
  setup do
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 24))
  end

  test "unauthenticated internal requests redirect to login" do
    get "/internal"

    assert_redirected_to "/login"
  end

  test "operator can login and logout with username and password" do
    operator = create_operator_with_credential!(role: "teller", username: "branch-user")
    credential = operator.credential
    credential.update!(failed_login_attempts: 2)

    post "/login", params: { username: "branch-user", password: "password123" }

    assert_redirected_to "/internal"
    assert_equal 0, credential.reload.failed_login_attempts
    assert_predicate credential.last_sign_in_at, :present?

    delete "/logout"
    assert_redirected_to "/login"

    get "/internal"
    assert_redirected_to "/login"
  end

  test "failed login increments failed attempts without locking" do
    operator = create_operator_with_credential!(role: "teller", username: "bad-login")
    credential = operator.credential

    post "/login", params: { username: "bad-login", password: "wrong-password" }

    assert_response :unauthorized
    assert_equal 1, credential.reload.failed_login_attempts
    assert_nil credential.locked_at
  end

  test "inactive operators cannot login" do
    create_operator_with_credential!(role: "teller", username: "inactive-login", active: false)

    post "/login", params: { username: "inactive-login", password: "password123" }

    assert_response :unauthorized
  end

  test "branch role gates allow teller and reject ops workspace" do
    create_operator_with_credential!(role: "teller", username: "teller-user")

    internal_login!(username: "teller-user")

    get "/branch"
    assert_response :success

    get "/ops"
    assert_response :forbidden

    get "/admin"
    assert_response :forbidden
  end

  test "operations role gates allow ops only" do
    create_operator_with_credential!(role: "operations", username: "ops-user")

    internal_login!(username: "ops-user")

    get "/ops"
    assert_response :success

    get "/branch"
    assert_response :forbidden

    get "/admin"
    assert_response :forbidden
  end

  test "admin role gates allow ops and admin" do
    create_operator_with_credential!(role: "admin", username: "admin-user")

    internal_login!(username: "admin-user")

    get "/ops"
    assert_response :success

    get "/admin"
    assert_response :success

    get "/branch"
    assert_response :forbidden
  end

  test "teller json api still uses operator header without browser login" do
    teller_operator, = create_workspace_operators!

    post "/teller/parties",
      params: { party_type: "individual", first_name: "Sam", last_name: "Rivera" }.to_json,
      headers: teller_json_headers(teller_operator)

    assert_response :created
  end
end
