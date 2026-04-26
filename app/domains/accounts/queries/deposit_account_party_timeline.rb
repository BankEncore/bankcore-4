# frozen_string_literal: true

module Accounts
  module Queries
    class DepositAccountPartyTimeline
      Result = Data.define(:party, :account, :current_rows, :historical_rows, :as_of)
      Row = Data.define(:relationship, :account, :party, :product)

      def self.call(party_record_id: nil, deposit_account_id: nil, as_of: nil)
        raise ArgumentError, "party_record_id or deposit_account_id is required" if party_record_id.blank? && deposit_account_id.blank?

        party = Party::Models::PartyRecord.find(party_record_id) if party_record_id.present?
        account = Models::DepositAccount.includes(:deposit_product).find(deposit_account_id) if deposit_account_id.present?
        effective_as_of = normalize_as_of(as_of)

        rows = scope_for(party: party, account: account)
          .map { |relationship| build_row(relationship) }
          .sort_by { |row| sort_key(row.relationship, effective_as_of) }

        Result.new(
          party: party,
          account: account,
          current_rows: rows.select { |row| current?(row.relationship, effective_as_of) },
          historical_rows: rows.reject { |row| current?(row.relationship, effective_as_of) },
          as_of: effective_as_of
        )
      end

      def self.scope_for(party:, account:)
        scope = Models::DepositAccountParty.includes(:party_record, deposit_account: :deposit_product)
        scope = scope.where(party_record_id: party.id) if party.present?
        scope = scope.where(deposit_account_id: account.id) if account.present?
        scope
      end
      private_class_method :scope_for

      def self.build_row(relationship)
        account = relationship.deposit_account
        Row.new(
          relationship: relationship,
          account: account,
          party: relationship.party_record,
          product: account.deposit_product
        )
      end
      private_class_method :build_row

      def self.current?(relationship, as_of)
        relationship.status == Models::DepositAccountParty::STATUS_ACTIVE &&
          relationship.effective_on <= as_of &&
          (relationship.ended_on.nil? || relationship.ended_on >= as_of)
      end
      private_class_method :current?

      def self.sort_key(relationship, as_of)
        [
          current?(relationship, as_of) ? 0 : 1,
          relationship.ended_on || Date.new(9999, 12, 31),
          relationship.effective_on,
          relationship.id
        ]
      end
      private_class_method :sort_key

      def self.normalize_as_of(value)
        return value.to_date if value.present?

        Core::BusinessDate::Services::CurrentBusinessDate.call
      rescue Core::BusinessDate::Errors::NotSet
        Date.current
      rescue ArgumentError, TypeError, NoMethodError
        raise ArgumentError, "as_of must be a valid date"
      end
      private_class_method :normalize_as_of
    end
  end
end
