# frozen_string_literal: true

module Accounts
  module Queries
    class DepositAccountsForParty
      Result = Data.define(:party, :rows)
      Row = Data.define(:relationship, :account, :product)

      def self.call(party_record_id:, include_inactive_parties: false)
        party = Party::Models::PartyRecord.find(party_record_id)
        scope = Models::DepositAccountParty
          .includes(deposit_account: :deposit_product)
          .where(party_record_id: party.id)
        scope = scope.where(status: Models::DepositAccountParty::STATUS_ACTIVE, ended_on: nil) unless include_inactive_parties

        rows = scope.sort_by { |relationship| sort_key(relationship) }.map do |relationship|
          account = relationship.deposit_account
          Row.new(relationship: relationship, account: account, product: account.deposit_product)
        end

        Result.new(party: party, rows: rows)
      end

      def self.sort_key(relationship)
        account = relationship.deposit_account
        [
          relationship.status == Models::DepositAccountParty::STATUS_ACTIVE ? 0 : 1,
          account.status == Models::DepositAccount::STATUS_OPEN ? 0 : 1,
          account.account_number
        ]
      end
      private_class_method :sort_key
    end
  end
end
