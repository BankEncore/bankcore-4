# frozen_string_literal: true

module Accounts
  module Commands
    class RebuildDepositBalanceProjection
      def self.call(deposit_account_id:, calculation_version: Models::DepositAccountBalanceProjection::CURRENT_CALCULATION_VERSION)
        new(deposit_account_id: deposit_account_id, calculation_version: calculation_version).call
      end

      def initialize(deposit_account_id:, calculation_version:)
        @deposit_account_id = deposit_account_id
        @calculation_version = calculation_version
      end

      def call
        Models::DepositAccount.find(deposit_account_id)

        Models::DepositAccountBalanceProjection.transaction do
          projection = locked_projection
          latest_entry = latest_journal_entry
          Services::DepositBalanceProjector.rebuild_projection!(
            projection,
            journal_entry: latest_entry,
            operational_event: latest_entry&.operational_event,
            as_of_business_date: latest_entry&.business_date || Core::BusinessDate::Services::CurrentBusinessDate.call
          )
          projection.update!(
            stale: false,
            stale_from_date: nil,
            calculation_version: calculation_version
          )
          projection
        end
      end

      private

      attr_reader :deposit_account_id, :calculation_version

      def locked_projection
        projection = Models::DepositAccountBalanceProjection.lock.find_by(deposit_account_id: deposit_account_id)
        return projection if projection

        Models::DepositAccountBalanceProjection.create!(deposit_account_id: deposit_account_id)
      rescue ActiveRecord::RecordNotUnique
        retry
      end

      def latest_journal_entry
        return nil if dda_account.nil?

        Core::Ledger::Models::JournalLine
          .joins(:journal_entry)
          .where(
            gl_account_id: dda_account.id,
            deposit_account_id: deposit_account_id
          )
          .order(
            "journal_entries.business_date DESC",
            "journal_entries.id DESC",
            "journal_lines.id DESC"
          )
          .first
          &.journal_entry
      end

      def dda_account
        @dda_account ||= Core::Ledger::Models::GlAccount.find_by(account_number: Services::AvailableBalanceResolver::GL_DDA)
      end
    end
  end
end
