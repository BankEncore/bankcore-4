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

  test "branch accept check deposit posts multiple structured items and shows hold when requested" do
    internal_login!(username: "chk-branch-html")

    idem = "br-int-chk-#{SecureRandom.hex(6)}"
    hold_idem = "#{idem}-hold"

    post branch_check_deposits_path, params: {
      check_deposit: {
        deposit_account_number: @account.account_number,
        currency: "USD",
        items: [
          {
            amount: "30.00",
            routing_number: "011000015",
            account_number: "0001234500",
            check_serial_number: "1001",
            classification: "on_us"
          },
          {
            amount: "12.75",
            routing_number: "021000021",
            account_number: "987654321",
            check_serial_number: "2055",
            classification: "transit"
          }
        ],
        hold_amount: "42.75",
        hold_idempotency_key: hold_idem,
        hold_expires_on: "2026-08-15",
        idempotency_key: idem
      }
    }

    assert_response :created
    assert_match(/Check deposit accepted/i, response.body)
    assert_match(/Hold scheduled release/i, response.body)

    ev = Core::OperationalEvents::Models::OperationalEvent.find_by!(channel: "teller", idempotency_key: idem)
    assert_equal "check.deposit.accepted", ev.event_type
    assert_equal "posted", ev.status
    assert_equal 4_275, ev.amount_minor_units
    assert_equal(
      {
        "items" => [
          {
            "amount_minor_units" => 3_000,
            "routing_number" => "011000015",
            "account_number" => "0001234500",
            "check_serial_number" => "1001",
            "classification" => "on_us"
          },
          {
            "amount_minor_units" => 1_275,
            "routing_number" => "021000021",
            "account_number" => "987654321",
            "check_serial_number" => "2055",
            "classification" => "transit"
          }
        ]
      },
      ev.payload
    )
    hold = Accounts::Models::Hold.find_by!(placed_for_operational_event_id: ev.id)
    assert_equal Date.new(2026, 8, 15), hold.expires_on
  end

  test "branch check deposit new is reachable from dashboard when deposit capability" do
    internal_login!(username: "chk-branch-html")
    get branch_path
    assert_response :success
    assert_select "a[href='#{new_branch_check_deposit_path}']", text: "Accept check deposit"
  end
end
