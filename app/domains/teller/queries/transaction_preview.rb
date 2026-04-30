# frozen_string_literal: true

module Teller
  module Queries
    class TransactionPreview
      CASH_IN_TYPES = %w[deposit].freeze
      CASH_OUT_TYPES = %w[withdrawal].freeze
      TRANSFER_TYPES = %w[transfer].freeze
      HOLD_TYPES = %w[hold].freeze
      CASH_TRANSFER_TYPES = %w[cash_transfer].freeze

      def self.call(...)
        new(...).call
      end

      def initialize(transaction_type:, amount_minor_units: nil, currency: "USD", deposit_account_id: nil,
        source_account_id: nil, destination_account_id: nil, teller_session_id: nil,
        source_cash_location_id: nil, destination_cash_location_id: nil)
        @transaction_type = transaction_type.to_s
        @amount_minor_units = amount_minor_units.to_i if amount_minor_units.present?
        @currency = currency.presence || "USD"
        @deposit_account_id = normalize_id(deposit_account_id)
        @source_account_id = normalize_id(source_account_id)
        @destination_account_id = normalize_id(destination_account_id)
        @teller_session_id = normalize_id(teller_session_id)
        @source_cash_location_id = normalize_id(source_cash_location_id)
        @destination_cash_location_id = normalize_id(destination_cash_location_id)
        @warnings = []
        @blockers = []
      end

      def call
        {
          transaction_type: transaction_type,
          amount_minor_units: amount_minor_units,
          currency: currency,
          teller_session: session_preview,
          drawer: drawer_preview,
          accounts: accounts_preview,
          cash_locations: cash_locations_preview,
          warnings: warnings,
          blockers: blockers
        }
      end

      private

      attr_reader :transaction_type, :amount_minor_units, :currency, :deposit_account_id, :source_account_id,
        :destination_account_id, :teller_session_id, :source_cash_location_id, :destination_cash_location_id,
        :warnings, :blockers

      def normalize_id(value)
        return nil if value.blank?

        value.to_i
      end

      def session_preview
        return nil unless teller_cash_transaction? || teller_session_id.present?

        if teller_session_id.blank?
          blockers << "Open teller session is required for teller cash activity."
          return nil
        end

        session = Teller::Models::TellerSession.includes(:cash_location).find_by(id: teller_session_id)
        if session.nil?
          blockers << "Teller session was not found."
          return nil
        end

        blockers << "Teller session is not open." unless session.status == Teller::Models::TellerSession::STATUS_OPEN

        {
          id: session.id,
          status: session.status,
          drawer_code: session.drawer_code,
          cash_location_id: session.cash_location_id,
          operating_unit_id: session.operating_unit_id
        }
      end

      def drawer_preview
        return nil unless teller_cash_transaction? && teller_session_id.present?

        current = Teller::Queries::ExpectedCashForSession.call(teller_session_id: teller_session_id)
        projected = if amount_minor_units.present?
          current + drawer_delta
        else
          current
        end

        {
          current_expected_cash_minor_units: current,
          projected_expected_cash_minor_units: projected,
          delta_minor_units: amount_minor_units.present? ? drawer_delta : 0
        }
      end

      def accounts_preview
        case transaction_type
        when *CASH_IN_TYPES, *CASH_OUT_TYPES
          { source: account_preview(deposit_account_id, account_delta_for_cash_transaction) }.compact
        when *TRANSFER_TYPES
          {
            source: account_preview(source_account_id, account_delta(-1)),
            destination: account_preview(destination_account_id, account_delta(1))
          }.compact
        when *HOLD_TYPES
          { source: account_preview(deposit_account_id, account_delta(-1)) }.compact
        else
          {}
        end
      end

      def account_preview(account_id, delta)
        return nil if account_id.blank?

        account = Accounts::Models::DepositAccount.find_by(id: account_id)
        if account.nil?
          blockers << "Deposit account ##{account_id} was not found."
          return nil
        end

        blockers << "Deposit account ##{account.id} is not open." unless account.status == Accounts::Models::DepositAccount::STATUS_OPEN

        current = Accounts::Services::AvailableBalanceMinorUnits.call(deposit_account_id: account.id)
        projected = delta.nil? ? current : current + delta
        warnings << "Projected available balance would be negative." if projected.negative?

        {
          id: account.id,
          account_number: account.account_number,
          status: account.status,
          current_available_balance_minor_units: current,
          projected_available_balance_minor_units: projected,
          delta_minor_units: delta || 0
        }
      end

      def cash_locations_preview
        return {} unless CASH_TRANSFER_TYPES.include?(transaction_type)

        {
          source: cash_location_preview(source_cash_location_id, account_delta(-1)),
          destination: cash_location_preview(destination_cash_location_id, account_delta(1))
        }.compact
      end

      def cash_location_preview(location_id, delta)
        return nil if location_id.blank?

        location = Cash::Models::CashLocation.includes(:cash_balance).find_by(id: location_id)
        if location.nil?
          blockers << "Cash location ##{location_id} was not found."
          return nil
        end

        blockers << "Cash location ##{location.id} is not active." unless location.active?
        current = location.cash_balance&.amount_minor_units.to_i
        projected = delta.nil? ? current : current + delta
        warnings << "Projected source cash location balance would be negative." if delta.to_i.negative? && projected.negative?

        {
          id: location.id,
          location_type: location.location_type,
          name: location.name,
          drawer_code: location.drawer_code,
          status: location.status,
          current_balance_minor_units: current,
          projected_balance_minor_units: projected,
          delta_minor_units: delta || 0
        }
      end

      def teller_cash_transaction?
        CASH_IN_TYPES.include?(transaction_type) || CASH_OUT_TYPES.include?(transaction_type)
      end

      def drawer_delta
        return 0 if amount_minor_units.blank?
        return amount_minor_units if CASH_IN_TYPES.include?(transaction_type)
        return -amount_minor_units if CASH_OUT_TYPES.include?(transaction_type)

        0
      end

      def account_delta_for_cash_transaction
        return nil if amount_minor_units.blank?
        return amount_minor_units if CASH_IN_TYPES.include?(transaction_type)
        return -amount_minor_units if CASH_OUT_TYPES.include?(transaction_type)

        nil
      end

      def account_delta(multiplier)
        return nil if amount_minor_units.blank?

        amount_minor_units * multiplier
      end
    end
  end
end
