# frozen_string_literal: true

require "test_helper"

class TellerHoldsDepositLinkedTest < ActionDispatch::IntegrationTest
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 22))

    @party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "H", last_name: "Ttp")
    @account = Accounts::Commands::OpenAccount.call(party_record_id: @party.id)
    @teller_operator, = create_workspace_operators!
    @cash_session_id = Teller::Commands::OpenSession.call(drawer_code: "http-hold-#{SecureRandom.hex(4)}").id

    @deposit_event = record_and_post_deposit!(40_000, "dep-http-#{SecureRandom.hex(4)}")
  end

  test "POST teller holds with placed_for_operational_event_id reduces available balance" do
    avail_before = Accounts::Services::AvailableBalanceMinorUnits.call(deposit_account_id: @account.id)

    post "/teller/holds",
      params: {
        hold: {
          deposit_account_id: @account.id,
          amount_minor_units: 7_500,
          currency: "USD",
          channel: "teller",
          idempotency_key: "hold-http-#{SecureRandom.hex(6)}",
          placed_for_operational_event_id: @deposit_event.id
        }
      }.to_json,
      headers: teller_json_headers(@teller_operator)

    assert_response :created
    body = response.parsed_body
    hold = Accounts::Models::Hold.find(body.fetch("hold_id"))
    assert_equal @deposit_event.id, hold.placed_for_operational_event_id

    avail_after = Accounts::Services::AvailableBalanceMinorUnits.call(deposit_account_id: @account.id)
    assert_equal avail_before - 7_500, avail_after
  end

  private

  def record_and_post_deposit!(amount, idem)
    r = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "teller",
      idempotency_key: idem,
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: @account.id,
      teller_session_id: @cash_session_id
    )
    Core::Posting::Commands::PostEvent.call(operational_event_id: r[:event].id)
    r[:event]
  end
end
