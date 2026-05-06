# frozen_string_literal: true

require "test_helper"

class BranchDepositTicketIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 8, 2))
    @operator = create_operator_with_credential!(role: "teller", username: "deposit-ticket-html")
    @party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Ticket", last_name: "Branch")
    @account = Accounts::Commands::OpenAccount.call(party_record_id: @party.id)
    @session = Teller::Commands::OpenSession.call(drawer_code: "ticket-html-#{SecureRandom.hex(4)}")
  end

  test "combined deposit form renders cash and check sections" do
    internal_login!(username: "deposit-ticket-html")

    get new_branch_deposit_ticket_path

    assert_response :success
    assert_includes response.body, "Combined deposit"
    assert_includes response.body, "Cash received"
    assert_includes response.body, "Check items"
    assert_includes response.body, "Check hold options"
    assert_includes response.body, 'data-controller="check-deposit-items"'
  end

  test "mixed combined deposit creates cash and check events with result links" do
    internal_login!(username: "deposit-ticket-html")
    idem = "branch-ticket-#{SecureRandom.hex(6)}"

    post branch_deposit_tickets_path, params: {
      deposit_ticket: {
        deposit_account_number: @account.account_number,
        teller_session_id: @session.id,
        cash_amount: "15.00",
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
        hold_amount: "20.00",
        hold_expires_on: "2026-08-15",
        idempotency_key: idem
      }
    }

    assert_response :created
    assert_match(/Combined deposit result/i, response.body)
    assert_match(/Cash event detail/i, response.body)
    assert_match(/Check event detail/i, response.body)

    cash_event = Core::OperationalEvents::Models::OperationalEvent.find_by!(channel: "teller", idempotency_key: "#{idem}:cash")
    check_event = Core::OperationalEvents::Models::OperationalEvent.find_by!(channel: "teller", idempotency_key: "#{idem}:checks")
    assert_equal "deposit.accepted", cash_event.event_type
    assert_equal "check.deposit.accepted", check_event.event_type
    assert_equal "posted", cash_event.status
    assert_equal "posted", check_event.status
    assert_equal 1_500, cash_event.amount_minor_units
    assert_equal 4_275, check_event.amount_minor_units
    assert_equal "deposit-ticket:#{idem}", cash_event.reference_id
    assert_equal cash_event.reference_id, check_event.reference_id

    hold = Accounts::Models::Hold.find_by!(placed_for_operational_event_id: check_event.id)
    assert_equal 2_000, hold.amount_minor_units
    assert_equal Date.new(2026, 8, 15), hold.expires_on
  end

  test "cash-only combined deposit works from combined workflow" do
    internal_login!(username: "deposit-ticket-html")
    idem = "branch-ticket-cash-#{SecureRandom.hex(6)}"

    post branch_deposit_tickets_path, params: {
      deposit_ticket: {
        deposit_account_number: @account.account_number,
        teller_session_id: @session.id,
        cash_amount: "10.00",
        currency: "USD",
        idempotency_key: idem
      }
    }

    assert_response :created
    assert Core::OperationalEvents::Models::OperationalEvent.exists?(channel: "teller", idempotency_key: "#{idem}:cash")
    refute Core::OperationalEvents::Models::OperationalEvent.exists?(channel: "teller", idempotency_key: "#{idem}:checks")
  end

  test "check-only combined deposit works from combined workflow" do
    internal_login!(username: "deposit-ticket-html")
    idem = "branch-ticket-check-#{SecureRandom.hex(6)}"

    post branch_deposit_tickets_path, params: {
      deposit_ticket: {
        deposit_account_number: @account.account_number,
        currency: "USD",
        items: [
          {
            amount: "10.00",
            routing_number: "011000015",
            account_number: "0001234500",
            check_serial_number: "3001"
          }
        ],
        idempotency_key: idem
      }
    }

    assert_response :created
    refute Core::OperationalEvents::Models::OperationalEvent.exists?(channel: "teller", idempotency_key: "#{idem}:cash")
    assert Core::OperationalEvents::Models::OperationalEvent.exists?(channel: "teller", idempotency_key: "#{idem}:checks")
  end
end
