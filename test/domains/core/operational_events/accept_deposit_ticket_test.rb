# frozen_string_literal: true

require "test_helper"

class AcceptDepositTicketTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 5, 6))

    @party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Ticket", last_name: "Deposit")
    @account = Accounts::Commands::OpenAccount.call(party_record_id: @party.id)
    @session = Teller::Commands::OpenSession.call(drawer_code: "ticket-#{SecureRandom.hex(4)}")
    @operator = Workspace::Models::Operator.create!(role: "teller", display_name: "Ticket Teller", active: true)
  end

  test "cash-only ticket creates and posts only cash deposit event" do
    idem = "ticket-cash-#{SecureRandom.hex(6)}"

    result = Core::OperationalEvents::Commands::AcceptDepositTicket.call(
      idempotency_key: idem,
      source_account_id: @account.id,
      teller_session_id: @session.id,
      actor_id: @operator.id,
      cash_amount_minor_units: 2_500
    )

    assert result[:cash_result]
    assert_nil result[:check_result]

    event = result[:cash_result].fetch(:operational_event).reload
    assert_equal "deposit.accepted", event.event_type
    assert_equal "posted", event.status
    assert_equal 2_500, event.amount_minor_units
    assert_equal "deposit-ticket:#{idem}", event.reference_id
    assert_equal "#{idem}:cash", event.idempotency_key
  end

  test "check-only ticket creates and posts only check deposit event" do
    idem = "ticket-check-#{SecureRandom.hex(6)}"
    payload = check_payload(3_000, "1001")

    result = Core::OperationalEvents::Commands::AcceptDepositTicket.call(
      idempotency_key: idem,
      source_account_id: @account.id,
      actor_id: @operator.id,
      check_amount_minor_units: 3_000,
      check_payload: payload
    )

    assert_nil result[:cash_result]
    event = result[:check_result].fetch(:operational_event).reload
    assert_equal "check.deposit.accepted", event.event_type
    assert_equal "posted", event.status
    assert_equal payload, event.payload
    assert_equal "deposit-ticket:#{idem}", event.reference_id
    assert_equal "#{idem}:checks", event.idempotency_key
  end

  test "mixed ticket creates both events atomically with optional check hold" do
    idem = "ticket-mixed-#{SecureRandom.hex(6)}"

    result = Core::OperationalEvents::Commands::AcceptDepositTicket.call(
      idempotency_key: idem,
      source_account_id: @account.id,
      teller_session_id: @session.id,
      actor_id: @operator.id,
      cash_amount_minor_units: 1_500,
      check_amount_minor_units: 3_000,
      check_payload: check_payload(3_000, "2001"),
      hold_amount_minor_units: 2_000,
      hold_expires_on: Date.new(2026, 5, 12)
    )

    cash_event = result[:cash_result].fetch(:operational_event).reload
    check_event = result[:check_result].fetch(:operational_event).reload
    assert_equal "deposit.accepted", cash_event.event_type
    assert_equal "check.deposit.accepted", check_event.event_type
    assert_equal "deposit-ticket:#{idem}", cash_event.reference_id
    assert_equal cash_event.reference_id, check_event.reference_id

    hold = result.fetch(:hold)
    assert_equal check_event.id, hold.placed_for_operational_event_id
    assert_equal 2_000, hold.amount_minor_units
    assert_equal Date.new(2026, 5, 12), hold.expires_on
  end

  test "replay returns same child events and already posted outcomes" do
    idem = "ticket-replay-#{SecureRandom.hex(6)}"
    args = {
      idempotency_key: idem,
      source_account_id: @account.id,
      teller_session_id: @session.id,
      actor_id: @operator.id,
      cash_amount_minor_units: 1_000,
      check_amount_minor_units: 2_000,
      check_payload: check_payload(2_000, "3001")
    }

    first = Core::OperationalEvents::Commands::AcceptDepositTicket.call(**args)
    second = Core::OperationalEvents::Commands::AcceptDepositTicket.call(**args)

    assert_equal first[:cash_result].fetch(:operational_event).id, second[:cash_result].fetch(:operational_event).id
    assert_equal first[:check_result].fetch(:operational_event).id, second[:check_result].fetch(:operational_event).id
    assert_equal :replay, second[:cash_result].fetch(:record_outcome)
    assert_equal :already_posted, second[:cash_result].fetch(:posting_outcome)
    assert_equal :replay, second[:check_result].fetch(:record_outcome)
    assert_equal :already_posted, second[:check_result].fetch(:posting_outcome)
  end

  test "check validation failure rolls back cash event creation" do
    idem = "ticket-rollback-#{SecureRandom.hex(6)}"
    bad_payload = {
      "items" => [
        { "amount_minor_units" => 2_000, "routing_number" => "011000015", "check_serial_number" => "4001" }
      ]
    }

    assert_raises(Core::OperationalEvents::Commands::AcceptDepositTicket::InvalidRequest) do
      Core::OperationalEvents::Commands::AcceptDepositTicket.call(
        idempotency_key: idem,
        source_account_id: @account.id,
        teller_session_id: @session.id,
        actor_id: @operator.id,
        cash_amount_minor_units: 1_000,
        check_amount_minor_units: 2_000,
        check_payload: bad_payload
      )
    end

    refute Core::OperationalEvents::Models::OperationalEvent.exists?(channel: "teller", idempotency_key: "#{idem}:cash")
    refute Core::OperationalEvents::Models::OperationalEvent.exists?(channel: "teller", idempotency_key: "#{idem}:checks")
  end

  test "check hold cannot exceed check total even when cash is present" do
    idem = "ticket-hold-cap-#{SecureRandom.hex(6)}"

    err = assert_raises(Core::OperationalEvents::Commands::AcceptDepositTicket::InvalidRequest) do
      Core::OperationalEvents::Commands::AcceptDepositTicket.call(
        idempotency_key: idem,
        source_account_id: @account.id,
        teller_session_id: @session.id,
        actor_id: @operator.id,
        cash_amount_minor_units: 5_000,
        check_amount_minor_units: 2_000,
        check_payload: check_payload(2_000, "5001"),
        hold_amount_minor_units: 3_000
      )
    end
    assert_match(/cannot exceed check total/, err.message)
  end

  private

  def check_payload(amount, serial)
    {
      "items" => [
        {
          "amount_minor_units" => amount,
          "routing_number" => "011000015",
          "account_number" => "0001234500",
          "check_serial_number" => serial
        }
      ]
    }
  end
end
