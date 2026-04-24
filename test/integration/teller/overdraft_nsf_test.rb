# frozen_string_literal: true

require "test_helper"

class TellerOverdraftNsfTest < ActionDispatch::IntegrationTest
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 22))
    @product = Products::Queries::FindDepositProduct.default_slice1!
    @teller_operator, = create_workspace_operators!
    @cash_session_id = Teller::Commands::OpenSession.call(drawer_code: "od-nsf-#{SecureRandom.hex(4)}").id
    @account = open_account!
    @destination = open_account!
  end

  test "teller withdrawal insufficient funds returns NSF denial and fee ids" do
    post "/teller/operational_events",
      params: {
        operational_event: {
          event_type: "withdrawal.posted",
          channel: "teller",
          idempotency_key: "teller-wd-nsf-#{SecureRandom.hex(4)}",
          amount_minor_units: 1_000,
          currency: "USD",
          source_account_id: @account.id,
          teller_session_id: @cash_session_id
        }
      }.to_json,
      headers: teller_json_headers(@teller_operator)

    assert_response :unprocessable_entity
    body = response.parsed_body
    assert_equal "nsf_denied", body.fetch("error")
    denial = Core::OperationalEvents::Models::OperationalEvent.find(body.fetch("denial_event_id"))
    fee = Core::OperationalEvents::Models::OperationalEvent.find(body.fetch("fee_event_id"))
    assert_equal "overdraft.nsf_denied", denial.event_type
    assert_equal "fee.assessed", fee.event_type
    assert_equal "posted", fee.status
  end

  test "teller transfer insufficient funds returns NSF denial and fee ids" do
    post "/teller/operational_events",
      params: {
        operational_event: {
          event_type: "transfer.completed",
          channel: "teller",
          idempotency_key: "teller-xfer-nsf-#{SecureRandom.hex(4)}",
          amount_minor_units: 1_000,
          currency: "USD",
          source_account_id: @account.id,
          destination_account_id: @destination.id
        }
      }.to_json,
      headers: teller_json_headers(@teller_operator)

    assert_response :unprocessable_entity
    body = response.parsed_body
    assert_equal "nsf_denied", body.fetch("error")
    denial = Core::OperationalEvents::Models::OperationalEvent.find(body.fetch("denial_event_id"))
    assert_equal "attempt:transfer.completed", denial.reference_id
    assert_equal @destination.id, denial.destination_account_id
  end

  private

  def open_account!
    party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "OD", last_name: SecureRandom.hex(3))
    Accounts::Commands::OpenAccount.call(party_record_id: party.id, deposit_product_id: @product.id)
  end
end
