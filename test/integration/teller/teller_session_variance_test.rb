# frozen_string_literal: true

require "test_helper"

class TellerSessionVarianceTest < ActionDispatch::IntegrationTest
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 22))
    @teller_operator, @supervisor_operator = create_workspace_operators!
    @saved_threshold = Rails.application.config.x.teller.variance_threshold_minor_units
    Rails.application.config.x.teller.variance_threshold_minor_units = 500
  end

  teardown do
    Rails.application.config.x.teller.variance_threshold_minor_units = @saved_threshold
  end

  test "close within variance threshold goes directly to closed" do
    sid = open_session!
    post "/teller/teller_sessions/close",
      params: {
        teller_session_close: {
          teller_session_id: sid,
          expected_cash_minor_units: 10_000,
          actual_cash_minor_units: 10_400
        }
      }.to_json,
      headers: teller_json_headers(@teller_operator)
    assert_response :success
    body = response.parsed_body
    assert_equal "closed", body["status"]
    assert_equal 400, body["variance_minor_units"]

    s = Teller::Models::TellerSession.find(sid)
    assert_equal "closed", s.status
    assert_predicate s.closed_at, :present?
    assert_nil s.supervisor_approved_at
  end

  test "close above threshold sets pending_supervisor without closed_at" do
    sid = open_session!
    post "/teller/teller_sessions/close",
      params: {
        teller_session_close: {
          teller_session_id: sid,
          expected_cash_minor_units: 10_000,
          actual_cash_minor_units: 11_000
        }
      }.to_json,
      headers: teller_json_headers(@teller_operator)
    assert_response :success
    body = response.parsed_body
    assert_equal "pending_supervisor", body["status"]
    assert_equal 1_000, body["variance_minor_units"]

    s = Teller::Models::TellerSession.find(sid)
    assert_equal "pending_supervisor", s.status
    assert_nil s.closed_at
    assert_nil s.supervisor_approved_at
  end

  test "approve_variance forbidden for teller" do
    sid = open_session!
    close_with_large_variance!(sid)

    post "/teller/teller_sessions/approve_variance",
      params: { teller_session_approve_variance: { teller_session_id: sid } }.to_json,
      headers: teller_json_headers(@teller_operator)
    assert_response :forbidden
  end

  test "approve_variance by supervisor closes session and records operator" do
    sid = open_session!
    close_with_large_variance!(sid)

    post "/teller/teller_sessions/approve_variance",
      params: { teller_session_approve_variance: { teller_session_id: sid } }.to_json,
      headers: teller_json_headers(@supervisor_operator)
    assert_response :success
    body = response.parsed_body
    assert_equal "closed", body["status"]
    assert_equal @supervisor_operator.id, body["supervisor_operator_id"]
    assert_predicate body["supervisor_approved_at"], :present?

    s = Teller::Models::TellerSession.find(sid)
    assert_equal "closed", s.status
    assert_equal @supervisor_operator.id, s.supervisor_operator_id
    assert_predicate s.closed_at, :present?
    assert_predicate s.supervisor_approved_at, :present?
  end

  test "approve_variance is idempotent when already approved" do
    sid = open_session!
    close_with_large_variance!(sid)

    2.times do
      post "/teller/teller_sessions/approve_variance",
        params: { teller_session_approve_variance: { teller_session_id: sid } }.to_json,
        headers: teller_json_headers(@supervisor_operator)
      assert_response :success
      assert_equal "closed", response.parsed_body["status"]
    end
  end

  test "approve_variance returns invalid_state for open session" do
    sid = open_session!
    post "/teller/teller_sessions/approve_variance",
      params: { teller_session_approve_variance: { teller_session_id: sid } }.to_json,
      headers: teller_json_headers(@supervisor_operator)
    assert_response :unprocessable_entity
    assert_equal "invalid_state", response.parsed_body["error"]
  end

  test "approve_variance rejects closed session that never was pending_supervisor" do
    sid = open_session!
    post "/teller/teller_sessions/close",
      params: {
        teller_session_close: {
          teller_session_id: sid,
          expected_cash_minor_units: 100,
          actual_cash_minor_units: 100
        }
      }.to_json,
      headers: teller_json_headers(@teller_operator)
    assert_response :success
    assert_equal "closed", response.parsed_body["status"]

    post "/teller/teller_sessions/approve_variance",
      params: { teller_session_approve_variance: { teller_session_id: sid } }.to_json,
      headers: teller_json_headers(@supervisor_operator)
    assert_response :unprocessable_entity
    assert_equal "invalid_state", response.parsed_body["error"]
  end

  test "approve_variance returns not_found for unknown id" do
    post "/teller/teller_sessions/approve_variance",
      params: { teller_session_approve_variance: { teller_session_id: 0 } }.to_json,
      headers: teller_json_headers(@supervisor_operator)
    assert_response :not_found
  end

  private

  def open_session!
    post "/teller/teller_sessions", params: {}.to_json, headers: teller_json_headers(@teller_operator)
    assert_response :created
    response.parsed_body["id"]
  end

  def close_with_large_variance!(sid)
    post "/teller/teller_sessions/close",
      params: {
        teller_session_close: {
          teller_session_id: sid,
          expected_cash_minor_units: 10_000,
          actual_cash_minor_units: 11_000
        }
      }.to_json,
      headers: teller_json_headers(@teller_operator)
    assert_response :success
  end
end
