# frozen_string_literal: true

require "test_helper"

class OpsClosePackageEodTest < ActionDispatch::IntegrationTest
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    @business_date = Date.new(2026, 9, 15)
    Core::BusinessDate::Commands::SetBusinessDate.call(on: @business_date)
    create_operator_with_credential!(role: "operations", username: "ops-close-pkg")
  end

  test "close package shows classification sections on current open day" do
    internal_login!(username: "ops-close-pkg")
    get ops_close_package_path
    assert_response :success
    assert_includes response.body, "Business date context"
    assert_includes response.body, "Can we close?"
    assert_includes response.body, "Classified evidence (primary buckets)"
    assert_includes response.body, "Close business date"
    refute_includes response.body, "Retrospective view"
  end

  test "historical business date shows retrospective banner and hides close submit" do
    internal_login!(username: "ops-close-pkg")
    post "/ops/business_date_close", params: { business_date: @business_date.iso8601 }
    assert_redirected_to "/ops/close_package"
    follow_redirect!
    assert_response :success

    get ops_close_package_path(business_date: @business_date.iso8601)
    assert_response :success
    assert_includes response.body, "Retrospective view"
    assert_includes response.body, "Close is only available from the close package for the"
    assert_select "input[type=submit][value='Close business date']", count: 0
  end

  test "failed close redirects back to close package with flash" do
    Teller::Commands::OpenSession.call(drawer_code: "blk-close-pkg-#{SecureRandom.hex(3)}")

    internal_login!(username: "ops-close-pkg")
    post "/ops/business_date_close", params: { business_date: @business_date.iso8601 }

    assert_redirected_to ops_close_package_path(business_date: @business_date.iso8601)
    assert_kind_of String, flash[:alert]
    assert flash[:alert].present?
  end

  test "future business date param is rejected on close package" do
    internal_login!(username: "ops-close-pkg")
    get ops_close_package_path(business_date: (@business_date + 1.day).iso8601)
    assert_response :unprocessable_entity
    assert_includes response.body, "cannot be after current business date"
  end
end
