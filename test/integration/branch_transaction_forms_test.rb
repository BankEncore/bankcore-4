# frozen_string_literal: true

require "test_helper"

class BranchTransactionFormsTest < ActionDispatch::IntegrationTest
  setup do
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 24))
  end

  test "teller-facing deposit, withdrawal, check deposit, and combined deposit forms render shared workflow sections" do
    create_operator_with_credential!(role: "teller", username: "branch-form-teller")

    internal_login!(username: "branch-form-teller")

    get new_branch_deposit_path
    assert_response :success
    assert_includes response.body, "Record deposit"
    assert_includes response.body, "Account and cash context"
    assert_includes response.body, "Transaction inputs"
    assert_includes response.body, "Review and submit"
    assert_includes response.body, 'data-controller="submit-state"'

    get new_branch_withdrawal_path
    assert_response :success
    assert_includes response.body, "Record withdrawal"
    assert_includes response.body, "Account and cash context"
    assert_includes response.body, "Transaction inputs"
    assert_includes response.body, "Review and submit"

    get new_branch_check_deposit_path
    assert_response :success
    assert_includes response.body, "Accept check deposit"
    assert_includes response.body, "Account and session context"
    assert_includes response.body, "Check items"
    assert_includes response.body, "Hold options"
    assert_includes response.body, "Review and submit"

    get new_branch_deposit_ticket_path
    assert_response :success
    assert_includes response.body, "Combined deposit"
    assert_includes response.body, "Account and session context"
    assert_includes response.body, "Cash received"
    assert_includes response.body, "Check items"
    assert_includes response.body, "Review and submit"
  end

  test "supervisor reversal form renders workflow sections" do
    create_operator_with_credential!(role: "supervisor", username: "branch-form-supervisor")

    internal_login!(username: "branch-form-supervisor")

    get new_branch_reversal_path
    assert_response :success
    assert_includes response.body, "Record reversal"
    assert_includes response.body, "Original event context"
    assert_includes response.body, "Review and submit"
    assert_includes response.body, "Supervisor-controlled action"
    assert_includes response.body, 'data-controller="submit-state"'
  end
end
