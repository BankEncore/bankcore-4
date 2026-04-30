# frozen_string_literal: true

require "test_helper"

class CashInventoryTest < ActiveSupport::TestCase
  setup do
    BankCore::Seeds::GlCoa.seed!
    BankCore::Seeds::Rbac.seed!
    Core::BusinessDate::Models::BusinessDateSetting.delete_all
    Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 4, 29))
    @operating_unit = Organization::Services::DefaultOperatingUnit.branch
    @teller = operator!("teller", "Cash Teller")
    @supervisor = operator!("supervisor", "Cash Supervisor")
    BankCore::Seeds::Rbac.seed!
  end

  test "opening teller session links a drawer cash location" do
    session = Teller::Commands::OpenSession.call(drawer_code: "A1", operator_id: @teller.id)

    assert_predicate session.cash_location, :present?
    assert_equal "teller_drawer", session.cash_location.location_type
    assert_equal "A1", session.cash_location.drawer_code
  end

  test "opening teller session rejects a drawer already in use" do
    Teller::Commands::OpenSession.call(drawer_code: "A2", operator_id: @teller.id)

    assert_raises(Teller::Commands::OpenSession::SessionAlreadyOpen) do
      Teller::Commands::OpenSession.call(drawer_code: "A2", operator_id: @supervisor.id)
    end
  end

  test "cash write commands enforce actor capabilities" do
    admin = operator!("admin", "Cash Admin")
    BankCore::Seeds::Rbac.seed!

    location_error = assert_raises(Cash::Commands::CreateLocation::InvalidRequest) do
      Cash::Commands::CreateLocation.call(
        location_type: "branch_vault",
        operating_unit_id: @operating_unit.id,
        actor_id: @teller.id,
        name: "Unauthorized vault"
      )
    end
    assert_includes location_error.message, Workspace::Authorization::CapabilityRegistry::CASH_LOCATION_MANAGE

    vault = vault!
    drawer = drawer!("AUTH")

    count_error = assert_raises(Cash::Commands::RecordCashCount::InvalidRequest) do
      Cash::Commands::RecordCashCount.call(
        cash_location_id: vault.id,
        counted_amount_minor_units: 10_000,
        expected_amount_minor_units: 0,
        actor_id: admin.id,
        idempotency_key: "unauthorized-count"
      )
    end
    assert_includes count_error.message, Workspace::Authorization::CapabilityRegistry::CASH_COUNT_RECORD

    transfer_error = assert_raises(Cash::Commands::TransferCash::InvalidRequest) do
      Cash::Commands::TransferCash.call(
        source_cash_location_id: vault.id,
        destination_cash_location_id: drawer.id,
        amount_minor_units: 1_000,
        actor_id: admin.id,
        idempotency_key: "unauthorized-transfer"
      )
    end
    assert_includes transfer_error.message, Workspace::Authorization::CapabilityRegistry::CASH_MOVEMENT_CREATE
  end

  test "inactive locations are blocked for new cash movements" do
    vault = vault!
    drawer = drawer!("INACTIVE")
    Cash::Commands::DeactivateLocation.call(cash_location_id: drawer.id)

    error = assert_raises(Cash::Commands::TransferCash::InvalidRequest) do
      Cash::Commands::TransferCash.call(
        source_cash_location_id: vault.id,
        destination_cash_location_id: drawer.id,
        amount_minor_units: 1_000,
        actor_id: @teller.id,
        idempotency_key: "inactive-drawer-transfer"
      )
    end

    assert_equal "cash locations must be active", error.message
  end

  test "vault transfer waits for approval and completes without journal entry" do
    vault = vault!
    drawer = drawer!("B1")
    Cash::Commands::RecordCashCount.call(
      cash_location_id: vault.id,
      counted_amount_minor_units: 10_000,
      expected_amount_minor_units: 0,
      actor_id: @teller.id,
      idempotency_key: "fund-vault"
    )

    movement = Cash::Commands::TransferCash.call(
      source_cash_location_id: vault.id,
      destination_cash_location_id: drawer.id,
      amount_minor_units: 2_500,
      actor_id: @teller.id,
      idempotency_key: "vault-to-drawer"
    )

    assert_equal "pending_approval", movement.status
    assert_nil movement.operational_event_id
    assert_equal 10_000, vault.cash_balance.reload.amount_minor_units

    movement = Cash::Commands::ApproveCashMovement.call(
      cash_movement_id: movement.id,
      approving_actor_id: @supervisor.id
    )

    assert_equal "completed", movement.status
    assert_equal 7_500, vault.cash_balance.reload.amount_minor_units
    assert_equal 2_500, drawer.cash_balance.reload.amount_minor_units
    assert_equal "cash.movement.completed", movement.operational_event.event_type
    assert_empty movement.operational_event.journal_entries
  end

  test "cash movement approval requires authority in the movement operating unit" do
    vault = vault!
    drawer = drawer!("B2")
    Cash::Commands::RecordCashCount.call(
      cash_location_id: vault.id,
      counted_amount_minor_units: 10_000,
      expected_amount_minor_units: 0,
      actor_id: @teller.id,
      idempotency_key: "fund-vault-scoped-approval"
    )
    movement = Cash::Commands::TransferCash.call(
      source_cash_location_id: vault.id,
      destination_cash_location_id: drawer.id,
      amount_minor_units: 2_500,
      actor_id: @teller.id,
      idempotency_key: "vault-to-drawer-scoped-approval"
    )
    scoped_supervisor = scoped_operator!("supervisor", "Other Branch Supervisor", other_branch!)

    assert_raises(Cash::Commands::ApproveCashMovement::InvalidState) do
      Cash::Commands::ApproveCashMovement.call(
        cash_movement_id: movement.id,
        approving_actor_id: scoped_supervisor.id
      )
    end

    grant_scoped_role!(scoped_supervisor, @operating_unit)
    approved = Cash::Commands::ApproveCashMovement.call(
      cash_movement_id: movement.id,
      approving_actor_id: scoped_supervisor.id
    )

    assert_equal "completed", approved.status
  end

  test "cash movement approval reports insufficient source balance without completing" do
    vault = vault!
    drawer = drawer!("B3")
    movement = Cash::Commands::TransferCash.call(
      source_cash_location_id: vault.id,
      destination_cash_location_id: drawer.id,
      amount_minor_units: 2_500,
      actor_id: @teller.id,
      idempotency_key: "vault-to-drawer-insufficient"
    )

    error = assert_raises(Cash::Commands::ApproveCashMovement::InvalidState) do
      Cash::Commands::ApproveCashMovement.call(
        cash_movement_id: movement.id,
        approving_actor_id: @supervisor.id
      )
    end

    assert_equal "source cash balance is insufficient", error.message
    assert_equal Cash::Models::CashMovement::STATUS_PENDING_APPROVAL, movement.reload.status
    assert_nil movement.operational_event_id
    assert_equal 0, vault.cash_balance.reload.amount_minor_units
    assert_equal 0, drawer.cash_balance.reload.amount_minor_units
  end

  test "cash count variance approval posts cash variance to GL once" do
    drawer = drawer!("C1")
    Cash::Commands::RecordCashCount.call(
      cash_location_id: drawer.id,
      counted_amount_minor_units: 1_000,
      expected_amount_minor_units: 0,
      actor_id: @teller.id,
      idempotency_key: "drawer-start"
    )

    count = Cash::Commands::RecordCashCount.call(
      cash_location_id: drawer.id,
      counted_amount_minor_units: 900,
      expected_amount_minor_units: 1_000,
      actor_id: @teller.id,
      idempotency_key: "drawer-count-short"
    )
    variance = count.cash_variance

    assert_equal(-100, variance.amount_minor_units)
    Cash::Commands::ApproveCashVariance.call(cash_variance_id: variance.id, approving_actor_id: @supervisor.id)

    variance.reload
    assert_equal "posted", variance.status
    event = variance.cash_variance_posted_event
    assert_equal "cash.variance.posted", event.event_type
    assert_equal "posted", event.status
    lines = event.journal_entries.sole.journal_lines.includes(:gl_account).order(:sequence_no)
    assert_equal "5190", lines.first.gl_account.account_number
    assert_equal "debit", lines.first.side
    assert_equal "1110", lines.second.gl_account.account_number
    assert_equal "credit", lines.second.side

    Cash::Commands::ApproveCashVariance.call(cash_variance_id: variance.id, approving_actor_id: @supervisor.id)
    assert_equal 1, Core::OperationalEvents::Models::OperationalEvent.where(event_type: "cash.variance.posted", reference_id: variance.id.to_s).count
  end

  test "cash variance approval requires authority in the variance operating unit" do
    drawer = drawer!("C2")
    Cash::Commands::RecordCashCount.call(
      cash_location_id: drawer.id,
      counted_amount_minor_units: 1_000,
      expected_amount_minor_units: 0,
      actor_id: @teller.id,
      idempotency_key: "drawer-start-scoped-variance"
    )
    count = Cash::Commands::RecordCashCount.call(
      cash_location_id: drawer.id,
      counted_amount_minor_units: 900,
      expected_amount_minor_units: 1_000,
      actor_id: @teller.id,
      idempotency_key: "drawer-count-scoped-variance"
    )
    scoped_supervisor = scoped_operator!("supervisor", "Other Branch Variance Supervisor", other_branch!)

    assert_raises(Cash::Commands::ApproveCashVariance::InvalidState) do
      Cash::Commands::ApproveCashVariance.call(
        cash_variance_id: count.cash_variance.id,
        approving_actor_id: scoped_supervisor.id
      )
    end

    grant_scoped_role!(scoped_supervisor, @operating_unit)
    variance = Cash::Commands::ApproveCashVariance.call(
      cash_variance_id: count.cash_variance.id,
      approving_actor_id: scoped_supervisor.id
    )

    assert_equal "posted", variance.status
  end

  test "external cash shipment receipt increases vault cash and posts GL" do
    vault = vault!

    movement = Cash::Commands::ReceiveExternalCashShipment.call(
      destination_cash_location_id: vault.id,
      amount_minor_units: 50_000,
      actor_id: @supervisor.id,
      idempotency_key: "fed-cash-receipt-1",
      external_source: "Federal Reserve",
      shipment_reference: "FRB-20260429-001"
    )

    assert_equal Cash::Models::CashMovement::STATUS_COMPLETED, movement.status
    assert_equal Cash::Models::CashMovement::TYPE_EXTERNAL_SHIPMENT_RECEIVED, movement.movement_type
    assert_nil movement.source_cash_location_id
    assert_equal vault.id, movement.destination_cash_location_id
    assert_equal "Federal Reserve", movement.external_source
    assert_equal "FRB-20260429-001", movement.shipment_reference
    assert_equal 50_000, vault.cash_balance.reload.amount_minor_units

    event = movement.operational_event
    assert_equal "cash.shipment.received", event.event_type
    assert_equal "posted", event.status
    assert_equal movement.id.to_s, event.reference_id
    lines = event.journal_entries.sole.journal_lines.includes(:gl_account).order(:sequence_no)
    assert_equal "1110", lines.first.gl_account.account_number
    assert_equal "debit", lines.first.side
    assert_equal "1130", lines.second.gl_account.account_number
    assert_equal "credit", lines.second.side
  end

  test "external cash shipment receipt is idempotent" do
    vault = vault!
    attrs = {
      destination_cash_location_id: vault.id,
      amount_minor_units: 25_000,
      actor_id: @supervisor.id,
      idempotency_key: "fed-cash-receipt-idempotent",
      external_source: "Correspondent Bank",
      shipment_reference: "CORR-001"
    }

    first = Cash::Commands::ReceiveExternalCashShipment.call(**attrs)

    assert_no_difference -> { Cash::Models::CashMovement.count } do
      assert_no_difference -> { Core::OperationalEvents::Models::OperationalEvent.count } do
        second = Cash::Commands::ReceiveExternalCashShipment.call(**attrs)
        assert_equal first.id, second.id
      end
    end
    assert_equal 25_000, vault.cash_balance.reload.amount_minor_units
    assert_equal 1, first.operational_event.journal_entries.count
  end

  test "cash count idempotency mismatch is rejected" do
    drawer = drawer!("COUNT-IDEMP")
    attrs = {
      cash_location_id: drawer.id,
      counted_amount_minor_units: 1_000,
      expected_amount_minor_units: 0,
      actor_id: @teller.id,
      idempotency_key: "count-idempotency-mismatch"
    }
    Cash::Commands::RecordCashCount.call(**attrs)

    assert_raises(Cash::Commands::RecordCashCount::MismatchedIdempotency) do
      Cash::Commands::RecordCashCount.call(**attrs.merge(counted_amount_minor_units: 2_000))
    end
  end

  test "external cash shipment receipt idempotency mismatch is rejected" do
    vault = vault!
    attrs = {
      destination_cash_location_id: vault.id,
      amount_minor_units: 25_000,
      actor_id: @supervisor.id,
      idempotency_key: "shipment-idempotency-mismatch",
      external_source: "Correspondent Bank",
      shipment_reference: "CORR-MISMATCH"
    }
    Cash::Commands::ReceiveExternalCashShipment.call(**attrs)

    assert_raises(Cash::Commands::ReceiveExternalCashShipment::MismatchedIdempotency) do
      Cash::Commands::ReceiveExternalCashShipment.call(**attrs.merge(amount_minor_units: 30_000))
    end
  end

  test "external cash shipment receipt requires shipment capability and branch vault destination" do
    drawer = drawer!("D1")

    assert_raises(Cash::Commands::ReceiveExternalCashShipment::InvalidRequest) do
      Cash::Commands::ReceiveExternalCashShipment.call(
        destination_cash_location_id: drawer.id,
        amount_minor_units: 10_000,
        actor_id: @supervisor.id,
        idempotency_key: "cash-receipt-drawer",
        external_source: "Federal Reserve",
        shipment_reference: "BAD-DEST"
      )
    end

    vault = vault!
    error = assert_raises(Cash::Commands::ReceiveExternalCashShipment::InvalidRequest) do
      Cash::Commands::ReceiveExternalCashShipment.call(
        destination_cash_location_id: vault.id,
        amount_minor_units: 10_000,
        actor_id: @teller.id,
        idempotency_key: "cash-receipt-unauthorized",
        external_source: "Federal Reserve",
        shipment_reference: "NO-AUTH"
      )
    end
    assert_includes error.message, "cash.shipment.receive"
  end

  private

  def operator!(role, name)
    Workspace::Models::Operator.create!(
      role: role,
      display_name: name,
      active: true,
      default_operating_unit: @operating_unit
    )
  end

  def scoped_operator!(role, name, operating_unit)
    operator = operator!(role, name)
    operator.operator_role_assignments.delete_all
    operator.update!(default_operating_unit: operating_unit)
    grant_scoped_role!(operator, operating_unit)
    operator
  end

  def grant_scoped_role!(operator, operating_unit)
    Workspace::Models::OperatorRoleAssignment.find_or_create_by!(
      operator: operator,
      role: role_for(operator.role),
      scope_type: "operating_unit",
      scope_id: operating_unit.id
    ) do |assignment|
      assignment.active = true
    end
  end

  def role_for(legacy_role)
    role_code = Workspace::Authorization::CapabilityRegistry::LEGACY_ROLE_MAPPING.fetch(legacy_role)
    Workspace::Models::Role.find_by!(code: role_code)
  end

  def other_branch!
    Organization::Models::OperatingUnit.create!(
      code: "OTHER-#{SecureRandom.hex(4)}",
      name: "Other Branch",
      unit_type: "branch",
      parent_operating_unit: Organization::Services::DefaultOperatingUnit.institution,
      status: "active",
      time_zone: "Eastern Time (US & Canada)",
      opened_on: Date.current
    )
  end

  def vault!
    Cash::Commands::CreateLocation.call(
      location_type: "branch_vault",
      operating_unit_id: @operating_unit.id,
      actor_id: @supervisor.id
    )
  end

  def drawer!(code)
    Cash::Commands::CreateLocation.call(
      location_type: "teller_drawer",
      drawer_code: code,
      operating_unit_id: @operating_unit.id,
      actor_id: @teller.id
    )
  end
end
