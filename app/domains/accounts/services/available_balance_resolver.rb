# frozen_string_literal: true

module Accounts
  module Services
    class AvailableBalanceResolver
      GL_DDA = "2110"

      Result = Data.define(
        :ledger_balance_minor_units,
        :hold_balance_minor_units,
        :available_balance_minor_units
      )

      def self.call(deposit_account_id:, ledger_balance_minor_units: nil)
        new(
          deposit_account_id: deposit_account_id,
          ledger_balance_minor_units: ledger_balance_minor_units
        ).call
      end

      def self.from_journal(deposit_account_id:)
        ledger = journal_ledger_balance_minor_units(deposit_account_id: deposit_account_id)
        new(deposit_account_id: deposit_account_id, ledger_balance_minor_units: ledger).call
      end

      def self.journal_ledger_balance_minor_units(deposit_account_id:)
        dda = Core::Ledger::Models::GlAccount.find_by(account_number: GL_DDA)
        return 0 if dda.nil?

        lines = Core::Ledger::Models::JournalLine.where(gl_account_id: dda.id, deposit_account_id: deposit_account_id)
        credits = lines.where(side: "credit").sum(:amount_minor_units)
        debits = lines.where(side: "debit").sum(:amount_minor_units)
        credits - debits
      end

      def initialize(deposit_account_id:, ledger_balance_minor_units:)
        @deposit_account_id = deposit_account_id
        @ledger_balance_minor_units = ledger_balance_minor_units
      end

      def call
        return projection_result if ledger_balance_minor_units.nil? && projection.present?

        ledger = ledger_balance_minor_units || self.class.journal_ledger_balance_minor_units(deposit_account_id: deposit_account_id)
        hold = active_hold_balance_minor_units
        Result.new(
          ledger_balance_minor_units: ledger,
          hold_balance_minor_units: hold,
          available_balance_minor_units: ledger - hold
        )
      end

      private

      attr_reader :deposit_account_id, :ledger_balance_minor_units

      def projection
        @projection ||= Accounts::Models::DepositAccountBalanceProjection.find_by(deposit_account_id: deposit_account_id)
      end

      def projection_result
        Result.new(
          ledger_balance_minor_units: projection.ledger_balance_minor_units,
          hold_balance_minor_units: projection.hold_balance_minor_units,
          available_balance_minor_units: projection.available_balance_minor_units
        )
      end

      def active_hold_balance_minor_units
        Accounts::Models::Hold.active_for_account(deposit_account_id).sum(:amount_minor_units)
      end
    end
  end
end
