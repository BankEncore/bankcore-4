# frozen_string_literal: true

require "test_helper"

class AcceptCheckDepositTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 22))

    @party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "C", last_name: "D")
    @account = Accounts::Commands::OpenAccount.call(party_record_id: @party.id)
    @session = Teller::Commands::OpenSession.call(drawer_code: "chk-dep-#{SecureRandom.hex(4)}")
    @operator = Workspace::Models::Operator.create!(role: "teller", display_name: "Chk Teller", active: true)
  end

  test "records posts dr 1160 cr 2110 and omits hold keys when no hold" do
    idem = "chk-#{SecureRandom.hex(6)}"
    payload = { "items" => [ { "amount_minor_units" => 4_500, "item_reference" => "MICR-1" } ] }

    r = Core::OperationalEvents::Commands::AcceptCheckDeposit.call(
      channel: "teller",
      idempotency_key: idem,
      amount_minor_units: 4_500,
      currency: "USD",
      source_account_id: @account.id,
      teller_session_id: @session.id,
      actor_id: @operator.id,
      payload: payload
    )

    assert_equal :created, r[:record_outcome]
    assert_equal :posted, r[:posting_outcome]
    assert_not r.key?(:hold_outcome)
    assert_nil r[:hold]

    ev = r[:operational_event].reload
    assert_equal "posted", ev.status
    assert_equal({ "items" => [ { "amount_minor_units" => 4_500, "item_reference" => "MICR-1" } ] }, ev.payload)

    entry = ev.journal_entries.order(:id).sole
    lines = entry.journal_lines.order(:sequence_no)
    assert_equal Core::Ledger::Models::GlAccount.find_by!(account_number: "1160").id, lines.find_by(side: "debit").gl_account_id
    credit = lines.find_by(side: "credit")
    assert_equal Core::Ledger::Models::GlAccount.find_by!(account_number: "2110").id, credit.gl_account_id
    assert_equal @account.id, credit.deposit_account_id
  end

  test "partial hold and orchestration replay is idempotent for event post and hold" do
    idem = "chk-h-#{SecureRandom.hex(6)}"
    hold_idem = "chk-h-hold-#{SecureRandom.hex(6)}"
    payload = {
      "items" => [
        { "amount_minor_units" => 3_000, "item_reference" => "A" },
        { "amount_minor_units" => 2_000, "serial_number" => "B" }
      ]
    }

    r1 = Core::OperationalEvents::Commands::AcceptCheckDeposit.call(
      channel: "teller",
      idempotency_key: idem,
      amount_minor_units: 5_000,
      currency: "USD",
      source_account_id: @account.id,
      actor_id: @operator.id,
      payload: payload,
      hold_amount_minor_units: 2_000,
      hold_idempotency_key: hold_idem
    )
    assert_equal :created, r1[:record_outcome]
    assert_equal :posted, r1[:posting_outcome]
    assert_equal :created, r1[:hold_outcome]
    dep_id = r1[:operational_event].id

    r2 = Core::OperationalEvents::Commands::AcceptCheckDeposit.call(
      channel: "teller",
      idempotency_key: idem,
      amount_minor_units: 5_000,
      currency: "USD",
      source_account_id: @account.id,
      actor_id: @operator.id,
      payload: payload,
      hold_amount_minor_units: 2_000,
      hold_idempotency_key: hold_idem
    )
    assert_equal :replay, r2[:record_outcome]
    assert_equal :already_posted, r2[:posting_outcome]
    assert_equal :replay, r2[:hold_outcome]
    assert_equal dep_id, r2[:operational_event].id
    assert_equal 1, Accounts::Models::Hold.where(placed_for_operational_event_id: dep_id).count
  end

  test "passes expires_on through to deposit-linked hold" do
    idem = "chk-exp-#{SecureRandom.hex(6)}"
    payload = { "items" => [ { "amount_minor_units" => 100, "item_reference" => "EXP-1" } ] }
    release_on = Date.new(2026, 5, 10)

    r = Core::OperationalEvents::Commands::AcceptCheckDeposit.call(
      channel: "teller",
      idempotency_key: idem,
      amount_minor_units: 100,
      currency: "USD",
      source_account_id: @account.id,
      actor_id: @operator.id,
      payload: payload,
      hold_amount_minor_units: 100,
      hold_idempotency_key: "#{idem}-hold",
      expires_on: release_on
    )

    assert_equal release_on, r[:hold].expires_on
  end

  test "requires distinct hold idempotency key when holding" do
    idem = "chk-same-#{SecureRandom.hex(4)}"
    payload = { "items" => [ { "amount_minor_units" => 100, "item_reference" => "X" } ] }

    err = assert_raises(Core::OperationalEvents::Commands::AcceptCheckDeposit::InvalidRequest) do
      Core::OperationalEvents::Commands::AcceptCheckDeposit.call(
        channel: "teller",
        idempotency_key: idem,
        amount_minor_units: 100,
        currency: "USD",
        source_account_id: @account.id,
        payload: payload,
        hold_amount_minor_units: 50,
        hold_idempotency_key: idem
      )
    end
    assert_match(/must differ/, err.message)
  end

  test "idempotency mismatch on replay raises from RecordEvent" do
    idem = "chk-mm-#{SecureRandom.hex(4)}"
    payload = { "items" => [ { "amount_minor_units" => 200, "item_reference" => "Y" } ] }

    Core::OperationalEvents::Commands::AcceptCheckDeposit.call(
      channel: "teller",
      idempotency_key: idem,
      amount_minor_units: 200,
      currency: "USD",
      source_account_id: @account.id,
      payload: payload
    )

    bad_payload = { "items" => [ { "amount_minor_units" => 200, "item_reference" => "Z" } ] }

    assert_raises(Core::OperationalEvents::Commands::RecordEvent::MismatchedIdempotency) do
      Core::OperationalEvents::Commands::AcceptCheckDeposit.call(
        channel: "teller",
        idempotency_key: idem,
        amount_minor_units: 200,
        currency: "USD",
        source_account_id: @account.id,
        payload: bad_payload
      )
    end
  end
end
