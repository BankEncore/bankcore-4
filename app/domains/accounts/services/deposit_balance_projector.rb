# frozen_string_literal: true

module Accounts
  module Services
    class DepositBalanceProjector
      GL_DDA = "2110"

      def self.apply_journal_entry!(journal_entry:)
        new(journal_entry: journal_entry).apply!
      end

      def initialize(journal_entry:)
        @journal_entry = journal_entry
      end

      def apply!
        deltas_by_account_id.map do |deposit_account_id, ledger_delta|
          projection, created = projection_for(deposit_account_id)
          if created
            rebuild_projection!(projection)
          else
            update_projection!(projection, ledger_delta)
          end
        end
      end

      private

      attr_reader :journal_entry

      def deltas_by_account_id
        @deltas_by_account_id ||= deposit_ledger_lines.each_with_object(Hash.new(0)) do |line, deltas|
          deltas[line.deposit_account_id] += signed_amount(line)
        end
      end

      def deposit_ledger_lines
        @deposit_ledger_lines ||= journal_entry
          .journal_lines
          .includes(:gl_account)
          .select { |line| line.deposit_account_id.present? && line.gl_account.account_number == GL_DDA }
      end

      def signed_amount(line)
        line.side == "credit" ? line.amount_minor_units : -line.amount_minor_units
      end

      def projection_for(deposit_account_id)
        projection = Models::DepositAccountBalanceProjection.lock.find_by(deposit_account_id: deposit_account_id)
        return [ projection, false ] if projection

        [ Models::DepositAccountBalanceProjection.create!(deposit_account_id: deposit_account_id), true ]
      rescue ActiveRecord::RecordNotUnique
        retry
      end

      def rebuild_projection!(projection)
        ledger = journal_ledger_balance_minor_units(projection.deposit_account_id)
        hold = hold_balance_minor_units(projection.deposit_account_id)
        projection.update!(
          ledger_balance_minor_units: ledger,
          hold_balance_minor_units: hold,
          available_balance_minor_units: ledger - hold,
          last_journal_entry: journal_entry,
          last_operational_event: journal_entry.operational_event,
          as_of_business_date: journal_entry.business_date,
          last_calculated_at: Time.current
        )
        projection
      end

      def update_projection!(projection, ledger_delta)
        ledger = projection.ledger_balance_minor_units + ledger_delta
        hold = hold_balance_minor_units(projection.deposit_account_id)
        projection.update!(
          ledger_balance_minor_units: ledger,
          hold_balance_minor_units: hold,
          available_balance_minor_units: ledger - hold,
          last_journal_entry: journal_entry,
          last_operational_event: journal_entry.operational_event,
          as_of_business_date: journal_entry.business_date,
          last_calculated_at: Time.current
        )
        projection
      end

      def journal_ledger_balance_minor_units(deposit_account_id)
        dda = Core::Ledger::Models::GlAccount.find_by!(account_number: GL_DDA)
        lines = Core::Ledger::Models::JournalLine.where(gl_account_id: dda.id, deposit_account_id: deposit_account_id)
        credits = lines.where(side: "credit").sum(:amount_minor_units)
        debits = lines.where(side: "debit").sum(:amount_minor_units)
        credits - debits
      end

      def hold_balance_minor_units(deposit_account_id)
        Models::Hold.active_for_account(deposit_account_id).sum(:amount_minor_units)
      end
    end
  end
end
