# frozen_string_literal: true

module Teller
  module Queries
    class TransactionPreview
      CASH_IN_TYPES = %w[deposit].freeze
      CASH_OUT_TYPES = %w[withdrawal].freeze
      TRANSFER_TYPES = %w[transfer].freeze
      HOLD_TYPES = %w[hold].freeze
      FEE_ASSESSMENT_TYPES = %w[fee_assessment].freeze
      FEE_WAIVER_TYPES = %w[fee_waiver].freeze
      CASH_TRANSFER_TYPES = %w[cash_transfer].freeze
      EVENT_TYPES = {
        "deposit" => "deposit.accepted",
        "withdrawal" => "withdrawal.posted",
        "transfer" => "transfer.completed",
        "hold" => "hold.placed",
        "fee_assessment" => "fee.assessed",
        "fee_waiver" => "fee.waived",
        "cash_transfer" => "cash.movement.completed"
      }.freeze

      def self.call(...)
        new(...).call
      end

      def initialize(transaction_type:, amount_minor_units: nil, currency: "USD", deposit_account_id: nil,
        source_account_id: nil, destination_account_id: nil, teller_session_id: nil,
        source_cash_location_id: nil, destination_cash_location_id: nil, record_and_post: nil)
        @transaction_type = transaction_type.to_s
        @amount_minor_units = amount_minor_units.to_i if amount_minor_units.present?
        @currency = currency.presence || "USD"
        @deposit_account_id = normalize_id(deposit_account_id)
        @source_account_id = normalize_id(source_account_id)
        @destination_account_id = normalize_id(destination_account_id)
        @teller_session_id = normalize_id(teller_session_id)
        @source_cash_location_id = normalize_id(source_cash_location_id)
        @destination_cash_location_id = normalize_id(destination_cash_location_id)
        @record_and_post = record_and_post
        @warnings = []
        @blockers = []
      end

      def call
        append_general_warnings
        {
          transaction_type: transaction_type,
          event: event_preview,
          amount_minor_units: amount_minor_units,
          currency: currency,
          cash_impact: cash_impact_preview,
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
        :record_and_post, :warnings, :blockers

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
        when *FEE_ASSESSMENT_TYPES
          { source: account_preview(deposit_account_id, account_delta(-1)) }.compact
        when *FEE_WAIVER_TYPES
          { source: account_preview(deposit_account_id, account_delta(1)) }.compact
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
        warnings << "Projected available balance would be negative; submit may create NSF denial or be rejected by command policy." if projected.negative?

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

      def event_preview
        entry = Core::OperationalEvents::EventCatalog.entry_for(EVENT_TYPES[transaction_type])
        return nil if entry.nil?

        {
          event_type: entry.event_type,
          category: entry.category,
          posts_to_gl: entry.posts_to_gl,
          reversible_via_posting_reversal: entry.reversible_via_posting_reversal,
          financial_impact: entry.financial_impact,
          description: entry.description
        }
      end

      def cash_impact_preview
        cash_in = CASH_IN_TYPES.include?(transaction_type) ? amount_minor_units.to_i : 0
        cash_out = CASH_OUT_TYPES.include?(transaction_type) ? amount_minor_units.to_i : 0
        return nil if cash_in.zero? && cash_out.zero?

        {
          cash_in_minor_units: cash_in,
          cash_out_minor_units: cash_out,
          net_cash_impact_minor_units: cash_in - cash_out
        }
      end

      def append_general_warnings
        if record_and_post.to_s == "0" && event_preview&.fetch(:posts_to_gl)
          warnings << "Record-only mode will leave a pending event until explicitly posted."
        end
        warnings << "Projected values may change if another event posts before submit." if amount_minor_units.present?
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
