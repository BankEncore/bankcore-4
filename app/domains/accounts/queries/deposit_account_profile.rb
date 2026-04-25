# frozen_string_literal: true

module Accounts
  module Queries
    class DepositAccountProfile
      Result = Data.define(
        :account,
        :product,
        :owners,
        :ledger_balance_minor_units,
        :available_balance_minor_units,
        :active_hold_total_minor_units,
        :current_business_date
      )

      def self.call(deposit_account_id:)
        account = Models::DepositAccount
          .includes(:deposit_product, deposit_account_parties: :party_record)
          .find(deposit_account_id)

        Result.new(
          account: account,
          product: account.deposit_product,
          owners: account.deposit_account_parties.sort_by { |owner| owner_sort_key(owner) },
          ledger_balance_minor_units: Services::AvailableBalanceMinorUnits.ledger_balance_minor_units(deposit_account_id: account.id),
          available_balance_minor_units: Services::AvailableBalanceMinorUnits.call(deposit_account_id: account.id),
          active_hold_total_minor_units: Models::Hold.active_for_account(account.id).sum(:amount_minor_units),
          current_business_date: current_business_date
        )
      end

      def self.owner_sort_key(owner)
        [
          owner.status == Models::DepositAccountParty::STATUS_ACTIVE ? 0 : 1,
          owner.role == Models::DepositAccountParty::ROLE_OWNER ? 0 : 1,
          owner.effective_on,
          owner.id
        ]
      end
      private_class_method :owner_sort_key

      def self.current_business_date
        Core::BusinessDate::Services::CurrentBusinessDate.call
      rescue Core::BusinessDate::Errors::NotSet
        nil
      end
      private_class_method :current_business_date
    end
  end
end
