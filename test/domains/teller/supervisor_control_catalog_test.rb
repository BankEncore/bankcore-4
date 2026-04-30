# frozen_string_literal: true

require "test_helper"

module Teller
  module Queries
    class SupervisorControlCatalogTest < ActiveSupport::TestCase
      setup do
        BankCore::Seeds::GlCoa.seed!
        BankCore::Seeds::Rbac.seed!
        Core::BusinessDate::Models::BusinessDateSetting.delete_all
        Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 10, 1))
        @operator = Workspace::Models::Operator.create!(
          role: "teller",
          display_name: "Catalog Teller",
          active: true,
          default_operating_unit: Organization::Services::DefaultOperatingUnit.branch
        )
      end

      test "describes supervisor-sensitive controls without mutating records" do
        session = Teller::Commands::OpenSession.call(drawer_code: "catalog-#{SecureRandom.hex(4)}", operator_id: @operator.id)
        session.update!(
          status: Teller::Models::TellerSession::STATUS_PENDING_SUPERVISOR,
          expected_cash_minor_units: 0,
          actual_cash_minor_units: 100,
          variance_minor_units: 100
        )
        before_count = Teller::Models::TellerSession.count

        result = SupervisorControlCatalog.call(operating_unit_id: @operator.default_operating_unit_id)

        assert_equal before_count, Teller::Models::TellerSession.count
        assert_includes result.controls.map(&:key), :teller_variance
        assert_includes result.controls.map(&:key), :cash_movement
        cash_control = result.controls.find { |control| control.key == :cash_movement }
        assert_equal Workspace::Authorization::CapabilityRegistry::CASH_MOVEMENT_APPROVE, cash_control.capability_code
        assert cash_control.no_self_approval
        assert_equal [ session.id ], result.pending.fetch(:teller_variances).map(&:id)
      end
    end
  end
end
