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
      operating_unit_id: operating_unit.id,
      actor_id: operator.id
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

  def create_drawer_variance_event!(amount_minor_units:)
    sid = Teller::Commands::OpenSession.call(drawer_code: "post-dv-#{SecureRandom.hex(4)}").id
    exp = 20_000
    act = exp + amount_minor_units
    Teller::Commands::CloseSession.call(
      teller_session_id: sid,
      expected_cash_minor_units: exp,
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
