# frozen_string_literal: true

module Accounts
  module Services
    class DepositBalanceProjector
      GL_DDA = "2110"

      def self.apply_journal_entry!(journal_entry:)
        new(journal_entry: journal_entry).apply!
      end

      def self.refresh_available_balance!(deposit_account_id:, operational_event: nil, as_of_business_date: nil)
        projection, created = projection_for(deposit_account_id)
        if created
          rebuild_projection!(
            projection,
            journal_entry: nil,
            operational_event: operational_event,
            as_of_business_date: as_of_business_date
          )
        else
          refresh_projection!(
            projection,
            operational_event: operational_event,
            as_of_business_date: as_of_business_date
          )
        end
      end

      def initialize(journal_entry:)
        @journal_entry = journal_entry
      end

      def apply!
        deltas_by_account_id.map do |deposit_account_id, ledger_delta|
          projection, created = self.class.projection_for(deposit_account_id)
          if created
            self.class.rebuild_projection!(projection, journal_entry: journal_entry, operational_event: journal_entry.operational_event,
              as_of_business_date: journal_entry.business_date)
          else
            update_projection!(projection, ledger_delta)
          end
        end
      end

      def self.projection_for(deposit_account_id)
        projection = Models::DepositAccountBalanceProjection.lock.find_by(deposit_account_id: deposit_account_id)
        return [ projection, false ] if projection

        [ Models::DepositAccountBalanceProjection.create!(deposit_account_id: deposit_account_id), true ]
      rescue ActiveRecord::RecordNotUnique
        retry
      end

      def self.rebuild_projection!(projection, journal_entry: nil, operational_event: nil, as_of_business_date: nil)
        resolved = AvailableBalanceResolver.from_journal(deposit_account_id: projection.deposit_account_id)
        projection.update!(
          ledger_balance_minor_units: resolved.ledger_balance_minor_units,
          hold_balance_minor_units: resolved.hold_balance_minor_units,
          available_balance_minor_units: resolved.available_balance_minor_units,
          last_journal_entry: journal_entry || projection.last_journal_entry,
          last_operational_event: operational_event || projection.last_operational_event,
          as_of_business_date: as_of_business_date || projection.as_of_business_date,
          last_calculated_at: Time.current
        )
        projection
      end

      def self.refresh_projection!(projection, operational_event: nil, as_of_business_date: nil)
        resolved = AvailableBalanceResolver.call(
          deposit_account_id: projection.deposit_account_id,
          ledger_balance_minor_units: projection.ledger_balance_minor_units
        )
        projection.update!(
          hold_balance_minor_units: resolved.hold_balance_minor_units,
          available_balance_minor_units: resolved.available_balance_minor_units,
          last_operational_event: operational_event || projection.last_operational_event,
          as_of_business_date: as_of_business_date || projection.as_of_business_date,
          last_calculated_at: Time.current
        )
        projection
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

      def update_projection!(projection, ledger_delta)
        ledger = projection.ledger_balance_minor_units + ledger_delta
        resolved = AvailableBalanceResolver.call(
          deposit_account_id: projection.deposit_account_id,
          ledger_balance_minor_units: ledger
        )
        projection.update!(
          ledger_balance_minor_units: resolved.ledger_balance_minor_units,
          hold_balance_minor_units: resolved.hold_balance_minor_units,
          available_balance_minor_units: resolved.available_balance_minor_units,
          last_journal_entry: journal_entry,
          last_operational_event: journal_entry.operational_event,
          as_of_business_date: journal_entry.business_date,
          last_calculated_at: Time.current
        )
        projection
      end
    end
  end
end
