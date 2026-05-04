# frozen_string_literal: true

require "test_helper"

class BranchCheckDepositIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 8, 1))
    create_operator_with_credential!(role: "teller", username: "chk-branch-html")
    @party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Chk", last_name: "Branch")
    @account = Accounts::Commands::OpenAccount.call(party_record_id: @party.id)
  end

  test "branch accept check deposit posts and shows hold when requested" do
    internal_login!(username: "chk-branch-html")

    idem = "br-int-chk-#{SecureRandom.hex(6)}"
    hold_idem = "#{idem}-hold"

    post branch_check_deposits_path, params: {
      check_deposit: {
        deposit_account_number: @account.account_number,
        amount: "42.75",
        currency: "USD",
        identity_kind: "reference",
        identity_value: "BR-CHK-REF",
        classification: "on_us",
        hold_amount: "42.75",
        hold_idempotency_key: hold_idem,
        idempotency_key: idem
      }
    }

    assert_response :created
    assert_match(/Check deposit accepted/i, response.body)
    assert_match(/Hold placed/i, response.body)

    ev = Core::OperationalEvents::Models::OperationalEvent.find_by!(channel: "teller", idempotency_key: idem)
    assert_equal "check.deposit.accepted", ev.event_type
    assert_equal "posted", ev.status
    assert_equal 4_275, ev.amount_minor_units
  end

  test "branch check deposit new is reachable from dashboard when deposit capability" do
    internal_login!(username: "chk-branch-html")
    get branch_path
    assert_response :success
    assert_select "a[href='#{new_branch_check_deposit_path}']", text: "Accept check deposit"
  end
end
