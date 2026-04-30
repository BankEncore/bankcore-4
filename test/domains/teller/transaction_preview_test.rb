# frozen_string_literal: true

require "test_helper"

module Teller
  module Queries
    class TransactionPreviewTest < ActiveSupport::TestCase
      setup do
        BankCore::Seeds::GlCoa.seed!
        Core::BusinessDate::Models::BusinessDateSetting.delete_all
        Core::BusinessDate::Commands::SetBusinessDate.call(on: Date.new(2026, 8, 2))
        BankCore::Seeds::Rbac.seed!
        @operator = Workspace::Models::Operator.create!(
          role: "teller",
          display_name: "Preview Teller",
          active: true,
          default_operating_unit: Organization::Services::DefaultOperatingUnit.branch
        )
        @product = Products::Queries::FindDepositProduct.default_slice1!
      end

      test "previews withdrawal drawer and account impact without writing events" do
        account = open_account!
        session = Teller::Commands::OpenSession.call(drawer_code: "preview-#{SecureRandom.hex(4)}", operator_id: @operator.id)
        fund_account!(account, session, 1_000)
        event_count = Core::OperationalEvents::Models::OperationalEvent.count

        preview = TransactionPreview.call(
          transaction_type: "withdrawal",
          deposit_account_id: account.id,
          amount_minor_units: 300,
          currency: "USD",
          teller_session_id: session.id
        )

        assert_equal event_count, Core::OperationalEvents::Models::OperationalEvent.count
        assert_empty preview[:blockers]
        assert_equal 1_000, preview.dig(:drawer, :current_expected_cash_minor_units)
        assert_equal 700, preview.dig(:drawer, :projected_expected_cash_minor_units)
        assert_equal 1_000, preview.dig(:accounts, :source, :current_available_balance_minor_units)
        assert_equal 700, preview.dig(:accounts, :source, :projected_available_balance_minor_units)
      end

      test "reports blocking issue for missing teller session on cash activity" do
        account = open_account!

        preview = TransactionPreview.call(
          transaction_type: "deposit",
          deposit_account_id: account.id,
          amount_minor_units: 500,
          currency: "USD"
        )

        assert_includes preview[:blockers], "Open teller session is required for teller cash activity."
        assert_equal 500, preview.dig(:accounts, :source, :projected_available_balance_minor_units)
      end

      test "previews cash custody movement balances" do
        vault = create_cash_location!(location_type: Cash::Models::CashLocation::TYPE_BRANCH_VAULT)
        drawer = create_cash_location!(
          location_type: Cash::Models::CashLocation::TYPE_TELLER_DRAWER,
          drawer_code: "preview-drawer-#{SecureRandom.hex(4)}"
        )
        create_cash_balance!(vault, 2_000)
        create_cash_balance!(drawer, 0)

        preview = TransactionPreview.call(
          transaction_type: "cash_transfer",
          source_cash_location_id: vault.id,
          destination_cash_location_id: drawer.id,
          amount_minor_units: 750,
          currency: "USD"
        )

        assert_empty preview[:blockers]
        assert_equal 2_000, preview.dig(:cash_locations, :source, :current_balance_minor_units)
        assert_equal 1_250, preview.dig(:cash_locations, :source, :projected_balance_minor_units)
        assert_equal 0, preview.dig(:cash_locations, :destination, :current_balance_minor_units)
        assert_equal 750, preview.dig(:cash_locations, :destination, :projected_balance_minor_units)
      end

      test "previews hold impact against available balance without writing events" do
        account = open_account!
        session = Teller::Commands::OpenSession.call(drawer_code: "hold-preview-#{SecureRandom.hex(4)}", operator_id: @operator.id)
        fund_account!(account, session, 1_500)
        event_count = Core::OperationalEvents::Models::OperationalEvent.count

        preview = TransactionPreview.call(
          transaction_type: "hold",
          deposit_account_id: account.id,
          amount_minor_units: 400,
          currency: "USD"
        )

        assert_equal event_count, Core::OperationalEvents::Models::OperationalEvent.count
        assert_empty preview[:blockers]
        assert_equal 1_500, preview.dig(:accounts, :source, :current_available_balance_minor_units)
        assert_equal 1_100, preview.dig(:accounts, :source, :projected_available_balance_minor_units)
      end

      test "previews fee assessment metadata and account impact" do
        account = open_account!
        session = Teller::Commands::OpenSession.call(drawer_code: "fee-preview-#{SecureRandom.hex(4)}", operator_id: @operator.id)
        fund_account!(account, session, 1_500)

        preview = TransactionPreview.call(
          transaction_type: "fee_assessment",
          deposit_account_id: account.id,
          amount_minor_units: 250,
          currency: "USD",
          record_and_post: "0"
        )

        assert_equal "fee.assessed", preview.dig(:event, :event_type)
        assert_equal "gl_posting", preview.dig(:event, :financial_impact)
        assert_equal 1_250, preview.dig(:accounts, :source, :projected_available_balance_minor_units)
        assert_includes preview[:warnings], "Record-only mode will leave a pending event until explicitly posted."
      end

      private

      def open_account!
        party = Party::Commands::CreateParty.call(
          party_type: "individual",
          first_name: "Preview",
          last_name: SecureRandom.hex(3)
        )
        Accounts::Commands::OpenAccount.call(party_record_id: party.id, deposit_product_id: @product.id)
      end

      def fund_account!(account, session, amount_minor_units)
        result = Core::OperationalEvents::Commands::RecordEvent.call(
          event_type: "deposit.accepted",
          channel: "teller",
          idempotency_key: "preview-funding-#{SecureRandom.hex(8)}",
          amount_minor_units: amount_minor_units,
          currency: "USD",
          source_account_id: account.id,
          teller_session_id: session.id,
          actor_id: @operator.id,
          operating_unit_id: @operator.default_operating_unit_id
        )
        Core::Posting::Commands::PostEvent.call(operational_event_id: result[:event].id)
      end

      def create_cash_location!(location_type:, drawer_code: nil)
        Cash::Models::CashLocation.create!(
          location_type: location_type,
          operating_unit: Organization::Services::DefaultOperatingUnit.branch,
          drawer_code: drawer_code,
          name: "#{location_type}-#{SecureRandom.hex(4)}",
          currency: "USD",
          status: Cash::Models::CashLocation::STATUS_ACTIVE
        )
      end

      def create_cash_balance!(location, amount_minor_units)
        Cash::Models::CashBalance.create!(
          cash_location: location,
          currency: "USD",
          amount_minor_units: amount_minor_units
        )
      end
    end
  end
end
