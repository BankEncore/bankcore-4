# frozen_string_literal: true

require "test_helper"

module Cash
  class AdminCashLocationCommandsTest < ActiveSupport::TestCase
    setup do
      BankCore::Seeds::OperatingUnits.seed!
      BankCore::Seeds::Rbac.seed!
      @operating_unit = Organization::Services::DefaultOperatingUnit.branch!
      @operator = Workspace::Models::Operator.create!(
        display_name: "Cash Admin Operator",
        role: "admin",
        active: true,
        default_operating_unit: @operating_unit
      )
    end

    test "updates location metadata without changing operating unit" do
      parent = create_location!("Parent Vault", Models::CashLocation::TYPE_INTERNAL_TRANSIT)
      location = create_location!("Managed Drawer", Models::CashLocation::TYPE_TELLER_DRAWER, drawer_code: "ADM1")

      Commands::UpdateLocation.call(
        cash_location_id: location.id,
        attributes: {
          name: "Updated Drawer",
          responsible_operator_id: @operator.id,
          parent_cash_location_id: parent.id,
          drawer_code: "ADM2",
          balancing_required: "0",
          external_reference: "drawer-ref"
        }
      )

      location.reload
      assert_equal "Updated Drawer", location.name
      assert_equal @operator.id, location.responsible_operator_id
      assert_equal parent.id, location.parent_cash_location_id
      assert_equal "ADM2", location.drawer_code
      assert_not location.balancing_required?
      assert_equal "drawer-ref", location.external_reference
      assert_equal @operating_unit.id, location.operating_unit_id
    end

    test "deactivates only zero balance locations" do
      location = create_location!("Zero Drawer", Models::CashLocation::TYPE_TELLER_DRAWER, drawer_code: "ZERO")
      Commands::DeactivateLocation.call(cash_location_id: location.id)
      assert_equal "inactive", location.reload.status

      funded = create_location!("Funded Drawer", Models::CashLocation::TYPE_TELLER_DRAWER, drawer_code: "FUND")
      funded.cash_balance.update!(amount_minor_units: 100)

      error = assert_raises(Commands::DeactivateLocation::InvalidRequest) do
        Commands::DeactivateLocation.call(cash_location_id: funded.id)
      end
      assert_match(/balance must be zero/, error.message)
    end

    test "blocks deactivation for open session pending movement and pending variance" do
      session_location = create_location!("Session Drawer", Models::CashLocation::TYPE_TELLER_DRAWER, drawer_code: "OPEN")
      Teller::Models::TellerSession.create!(
        status: Teller::Models::TellerSession::STATUS_OPEN,
        opened_at: Time.current,
        drawer_code: "OPEN",
        operating_unit: @operating_unit,
        cash_location: session_location
      )

      error = assert_raises(Commands::DeactivateLocation::InvalidRequest) do
        Commands::DeactivateLocation.call(cash_location_id: session_location.id)
      end
      assert_match(/open teller session/, error.message)

      movement_location = create_location!("Movement Drawer", Models::CashLocation::TYPE_TELLER_DRAWER, drawer_code: "MOVE")
      destination = create_location!("Transit", Models::CashLocation::TYPE_INTERNAL_TRANSIT)
      Models::CashMovement.create!(
        source_cash_location: movement_location,
        destination_cash_location: destination,
        operating_unit: @operating_unit,
        actor: @operator,
        amount_minor_units: 100,
        currency: "USD",
        business_date: Date.current,
        status: Models::CashMovement::STATUS_PENDING_APPROVAL,
        movement_type: Models::CashMovement::TYPE_INTERNAL_TRANSFER,
        idempotency_key: "pending-movement-#{SecureRandom.hex(4)}",
        request_fingerprint: SecureRandom.hex(16)
      )

      error = assert_raises(Commands::DeactivateLocation::InvalidRequest) do
        Commands::DeactivateLocation.call(cash_location_id: movement_location.id)
      end
      assert_match(/pending cash movement/, error.message)

      variance_location = create_location!("Variance Drawer", Models::CashLocation::TYPE_TELLER_DRAWER, drawer_code: "VAR")
      count = Models::CashCount.create!(
        cash_location: variance_location,
        operating_unit: @operating_unit,
        actor: @operator,
        counted_amount_minor_units: 0,
        expected_amount_minor_units: 0,
        currency: "USD",
        business_date: Date.current,
        status: Models::CashCount::STATUS_RECORDED,
        idempotency_key: "pending-variance-count-#{SecureRandom.hex(4)}",
        request_fingerprint: SecureRandom.hex(16)
      )
      Models::CashVariance.create!(
        cash_location: variance_location,
        cash_count: count,
        operating_unit: @operating_unit,
        actor: @operator,
        amount_minor_units: 100,
        currency: "USD",
        business_date: Date.current,
        status: Models::CashVariance::STATUS_PENDING_APPROVAL
      )

      error = assert_raises(Commands::DeactivateLocation::InvalidRequest) do
        Commands::DeactivateLocation.call(cash_location_id: variance_location.id)
      end
      assert_match(/pending cash variance/, error.message)
    end

    private

    def create_location!(name, type, drawer_code: nil)
      Commands::CreateLocation.call(
        location_type: type,
        operating_unit: @operating_unit,
        name: name,
        drawer_code: drawer_code
      )
    end
  end
end
