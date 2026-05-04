# frozen_string_literal: true

require "test_helper"

class CorePostingPostEventTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 22))
    party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Q", last_name: "R")
    @account = Accounts::Commands::OpenAccount.call(party_record_id: party.id)
    @saved_threshold = Rails.application.config.x.teller.variance_threshold_minor_units
    Rails.application.config.x.teller.variance_threshold_minor_units = 500
  end

  teardown do
    Rails.application.config.x.teller.variance_threshold_minor_units = @saved_threshold
  end

  test "posts check deposit dr 1160 cr 2110" do
    ev = create_pending_check_deposit_event!(amount: 9_999)
    r = Core::Posting::Commands::PostEvent.call(operational_event_id: ev.id)
    assert_equal :posted, r[:outcome]
    entry = ev.reload.posting_batches.sole.journal_entries.sole
    lines = entry.journal_lines.order(:sequence_no)
    assert_equal Core::Ledger::Models::GlAccount.find_by!(account_number: "1160").id, lines.find_by(side: "debit").gl_account_id
    credit = lines.find_by(side: "credit")
    assert_equal Core::Ledger::Models::GlAccount.find_by!(account_number: "2110").id, credit.gl_account_id
    assert_equal @account.id, credit.deposit_account_id
  end

  test "posts balanced 1110/2110 and marks event posted" do
    ev = create_pending_event!(amount: 12_34)
    r = Core::Posting::Commands::PostEvent.call(operational_event_id: ev.id)
    assert_equal :posted, r[:outcome]
    assert_equal "posted", ev.reload.status
    batch = ev.posting_batches.sole
    assert_equal "posted", batch.status
    entry = batch.journal_entries.sole
    lines = entry.journal_lines.order(:sequence_no)
    assert_equal 2, lines.size
    assert_equal 12_34, lines.sum { |l| l.side == "debit" ? l.amount_minor_units : 0 }
    assert_equal 12_34, lines.sum { |l| l.side == "credit" ? l.amount_minor_units : 0 }
    assert_equal Core::Ledger::Models::GlAccount.find_by!(account_number: "1110").id, lines.find_by(side: "debit").gl_account_id
    credit = lines.find_by(side: "credit")
    assert_equal Core::Ledger::Models::GlAccount.find_by!(account_number: "2110").id, credit.gl_account_id
    assert_equal @account.id, credit.deposit_account_id

    projection = @account.deposit_account_balance_projection
    assert_equal 12_34, projection.ledger_balance_minor_units
    assert_equal 12_34, projection.available_balance_minor_units
    assert_equal entry.id, projection.last_journal_entry_id
    assert_equal ev.id, projection.last_operational_event_id
    assert_equal Date.new(2026, 4, 22), projection.as_of_business_date
    assert projection.last_calculated_at
  end

  test "second post is idempotent" do
    ev = create_pending_event!(amount: 100)
    Core::Posting::Commands::PostEvent.call(operational_event_id: ev.id)
    r = Core::Posting::Commands::PostEvent.call(operational_event_id: ev.id)
    assert_equal :already_posted, r[:outcome]
    assert_equal 1, ev.reload.posting_batches.count
  end

  test "rolls back and leaves event pending when GL is missing" do
    ev = create_pending_event!(amount: 200)
    cash = Core::Ledger::Models::GlAccount.find_by!(account_number: "1110")
    prior = cash.account_number
    cash.update_column(:account_number, "1110-tmp-missing")
    assert_raises(ActiveRecord::RecordNotFound) do
      Core::Posting::Commands::PostEvent.call(operational_event_id: ev.id)
    end
    cash.update_column(:account_number, prior)
    assert_equal "pending", ev.reload.status
    assert_equal 0, ev.posting_batches.count
  end

  test "rolls back journal lines when projection update fails after line creation" do
    ev = create_pending_event!(amount: 300)
    original_projector = Accounts::Services::DepositBalanceProjector.method(:apply_journal_entry!)
    Accounts::Services::DepositBalanceProjector.define_singleton_method(:apply_journal_entry!) do |journal_entry:|
      raise "projection failure"
    end

    begin
      assert_raises(RuntimeError) do
        Core::Posting::Commands::PostEvent.call(operational_event_id: ev.id)
      end
    ensure
      Accounts::Services::DepositBalanceProjector.define_singleton_method(:apply_journal_entry!) do |journal_entry:|
        original_projector.call(journal_entry: journal_entry)
      end
    end

    assert_equal "pending", ev.reload.status
    assert_equal 0, ev.posting_batches.count
    assert_equal 0, Core::Ledger::Models::JournalEntry.joins(:posting_batch).where(posting_batches: { operational_event_id: ev.id }).count
    assert_equal 0, @account.deposit_account_balance_projection.reload.ledger_balance_minor_units
  end

  test "not found raises" do
    assert_raises(Core::Posting::Commands::PostEvent::NotFound) do
      Core::Posting::Commands::PostEvent.call(operational_event_id: 0)
    end
  end

  test "posts teller.drawer.variance.posted shortage as Dr 5190 Cr 1110" do
    ev = create_drawer_variance_event!(amount_minor_units: -250)
    Core::Posting::Commands::PostEvent.call(operational_event_id: ev.id)
    lines = ev.reload.posting_batches.sole.journal_entries.sole.journal_lines.order(:sequence_no)
    dr = lines.find_by(side: "debit")
    cr = lines.find_by(side: "credit")
    assert_equal "5190", dr.gl_account.account_number
    assert_equal "1110", cr.gl_account.account_number
    assert_equal 250, dr.amount_minor_units
  end

  test "posts teller.drawer.variance.posted overage as Dr 1110 Cr 5190" do
    ev = create_drawer_variance_event!(amount_minor_units: 180)
    Core::Posting::Commands::PostEvent.call(operational_event_id: ev.id)
    lines = ev.reload.posting_batches.sole.journal_entries.sole.journal_lines.order(:sequence_no)
    dr = lines.find_by(side: "debit")
    cr = lines.find_by(side: "credit")
    assert_equal "1110", dr.gl_account.account_number
    assert_equal "5190", cr.gl_account.account_number
  end

  test "posts fee.assessed as Dr 2110 Cr 4510" do
    fund_account!(25_000)
    fee = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "fee.assessed",
      channel: "batch",
      idempotency_key: "fee-a-#{SecureRandom.hex(4)}",
      amount_minor_units: 500,
      currency: "USD",
      source_account_id: @account.id
    )[:event]
    Core::Posting::Commands::PostEvent.call(operational_event_id: fee.id)
    lines = fee.reload.posting_batches.sole.journal_entries.sole.journal_lines.order(:sequence_no)
    dr = lines.find_by(side: "debit")
    cr = lines.find_by(side: "credit")
    assert_equal "2110", dr.gl_account.account_number
    assert_equal @account.id, dr.deposit_account_id
    assert_equal "4510", cr.gl_account.account_number
    assert_nil cr.deposit_account_id
    assert_equal 24_500, @account.deposit_account_balance_projection.reload.ledger_balance_minor_units
  end

  test "posts fee.waived as Dr 4510 Cr 2110" do
    fund_account!(30_000)
    assessed = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "fee.assessed",
      channel: "batch",
      idempotency_key: "fee-b-#{SecureRandom.hex(4)}",
      amount_minor_units: 400,
      currency: "USD",
      source_account_id: @account.id
    )[:event]
    Core::Posting::Commands::PostEvent.call(operational_event_id: assessed.id)
    waived = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "fee.waived",
      channel: "batch",
      idempotency_key: "fee-w-#{SecureRandom.hex(4)}",
      amount_minor_units: 400,
      currency: "USD",
      source_account_id: @account.id,
      reference_id: assessed.id.to_s
    )[:event]
    Core::Posting::Commands::PostEvent.call(operational_event_id: waived.id)
    lines = waived.reload.posting_batches.sole.journal_entries.sole.journal_lines.order(:sequence_no)
    dr = lines.find_by(side: "debit")
    cr = lines.find_by(side: "credit")
    assert_equal "4510", dr.gl_account.account_number
    assert_equal "2110", cr.gl_account.account_number
    assert_equal @account.id, cr.deposit_account_id
    assert_equal 30_000, @account.deposit_account_balance_projection.reload.ledger_balance_minor_units
  end

  test "updates projections for both sides of a transfer" do
    destination_party = Party::Commands::CreateParty.call(party_type: "individual", first_name: "Dest", last_name: "Projection")
    destination = Accounts::Commands::OpenAccount.call(party_record_id: destination_party.id)
    fund_account!(10_000)
    transfer = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "transfer.completed",
      channel: "batch",
      idempotency_key: "transfer-projection-#{SecureRandom.hex(4)}",
      amount_minor_units: 2_500,
      currency: "USD",
      source_account_id: @account.id,
      destination_account_id: destination.id
    )[:event]

    Core::Posting::Commands::PostEvent.call(operational_event_id: transfer.id)

    assert_equal 7_500, @account.deposit_account_balance_projection.reload.ledger_balance_minor_units
    assert_equal 2_500, destination.deposit_account_balance_projection.reload.ledger_balance_minor_units
  end

  test "recalculates available balance using active holds when posting updates projection" do
    Accounts::Models::Hold.create!(
      deposit_account: @account,
      amount_minor_units: 300,
      currency: "USD",
      status: Accounts::Models::Hold::STATUS_ACTIVE,
      hold_type: Accounts::Models::Hold::HOLD_TYPE_ADMINISTRATIVE,
      reason_code: Accounts::Models::Hold::REASON_MANUAL_REVIEW,
      expires_on: Date.new(2026, 4, 25)
    )

    ev = create_pending_event!(amount: 1_000)
    Core::Posting::Commands::PostEvent.call(operational_event_id: ev.id)

    projection = @account.deposit_account_balance_projection.reload
    assert_equal 1_000, projection.ledger_balance_minor_units
    assert_equal 300, projection.hold_balance_minor_units
    assert_equal 700, projection.available_balance_minor_units
  end

  test "posting reversal updates deposit balance projection with mirrored 2110 lines" do
    ev = create_pending_event!(amount: 1_200)
    Core::Posting::Commands::PostEvent.call(operational_event_id: ev.id)
    reversal = Core::OperationalEvents::Commands::RecordReversal.call(
      original_operational_event_id: ev.id,
      channel: "api",
      idempotency_key: "projection-reversal-#{SecureRandom.hex(4)}"
    )[:event]

    Core::Posting::Commands::PostEvent.call(operational_event_id: reversal.id)

    projection = @account.deposit_account_balance_projection.reload
    assert_equal 0, projection.ledger_balance_minor_units
    assert_equal reversal.id, projection.last_operational_event_id
  end

  test "posts cash shipment received as Dr 1110 Cr 1130" do
    operating_unit = Organization::Services::DefaultOperatingUnit.branch
    operator = Workspace::Models::Operator.create!(
      role: "supervisor",
      display_name: "Cash Shipment Supervisor",
      active: true,
      default_operating_unit: operating_unit
    )
    vault = Cash::Commands::CreateLocation.call(
      location_type: "branch_vault",
      operating_unit: operating_unit
    )
    movement = Cash::Models::CashMovement.create!(
      destination_cash_location: vault,
      operating_unit: operating_unit,
      actor: operator,
      amount_minor_units: 75_000,
      currency: "USD",
      business_date: Date.new(2026, 4, 22),
      status: Cash::Models::CashMovement::STATUS_COMPLETED,
      movement_type: Cash::Models::CashMovement::TYPE_EXTERNAL_SHIPMENT_RECEIVED,
      external_source: "Federal Reserve",
      shipment_reference: "POST-FRB-001",
      idempotency_key: "post-cash-shipment-movement",
      request_fingerprint: "post-cash-shipment-fingerprint",
      completed_at: Time.current
    )
    event = Core::OperationalEvents::Models::OperationalEvent.create!(
      event_type: "cash.shipment.received",
      status: "pending",
      business_date: Date.new(2026, 4, 22),
      channel: "branch",
      idempotency_key: "post-cash-shipment-event",
      amount_minor_units: 75_000,
      currency: "USD",
      actor: operator,
      operating_unit: operating_unit,
      reference_id: movement.id.to_s
    )

    Core::Posting::Commands::PostEvent.call(operational_event_id: event.id)

    lines = event.reload.posting_batches.sole.journal_entries.sole.journal_lines.includes(:gl_account).order(:sequence_no)
    assert_equal "1110", lines.first.gl_account.account_number
    assert_equal "debit", lines.first.side
    assert_equal "1130", lines.second.gl_account.account_number
    assert_equal "credit", lines.second.side
    projection = @account.reload.deposit_account_balance_projection
    assert_equal 0, projection.ledger_balance_minor_units
    assert_nil projection.last_journal_entry_id
  end

  private

  def fund_account!(amount)
    ev = Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "batch",
      idempotency_key: "fund-#{SecureRandom.hex(6)}",
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: @account.id
    )[:event]
    Core::Posting::Commands::PostEvent.call(operational_event_id: ev.id)
  end

  def create_pending_event!(amount:)
    Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "deposit.accepted",
      channel: "batch",
      idempotency_key: "post-test-#{SecureRandom.hex(6)}",
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: @account.id
    )[:event]
  end

  def create_pending_check_deposit_event!(amount:)
    payload = { "items" => [ { "amount_minor_units" => amount, "item_reference" => "chk-post-#{SecureRandom.hex(4)}" } ] }
    Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "check.deposit.accepted",
      channel: "teller",
      idempotency_key: "chk-post-test-#{SecureRandom.hex(6)}",
      amount_minor_units: amount,
      currency: "USD",
      source_account_id: @account.id,
      payload: payload
    )[:event]
  end

  def create_drawer_variance_event!(amount_minor_units:)
    sid = Teller::Commands::OpenSession.call(drawer_code: "post-dv-#{SecureRandom.hex(4)}").id
    exp = 20_000
    act = exp + amount_minor_units
    Teller::Models::TellerSession.find(sid).update!(opening_cash_minor_units: exp)
    Teller::Commands::CloseSession.call(
      teller_session_id: sid,
      actual_cash_minor_units: act
    )
    Core::OperationalEvents::Commands::RecordEvent.call(
      event_type: "teller.drawer.variance.posted",
      channel: "system",
      idempotency_key: "drawer-variance-#{sid}",
      amount_minor_units: amount_minor_units,
      currency: "USD",
      teller_session_id: sid
    )[:event]
  end
end
