# frozen_string_literal: true

module Accounts
  module Commands
    class OpenAccount
      class PartyNotFound < StandardError; end

      # @param party_record_id [Integer]
      # @param effective_on [Date, nil] defaults to Core::BusinessDate
      def self.call(party_record_id:, effective_on: nil)
        begin
          Party::Queries::FindParty.by_id(party_record_id)
        rescue ActiveRecord::RecordNotFound
          raise PartyNotFound, "party_record_id=#{party_record_id} not found"
        end

        on_date = effective_on || Core::BusinessDate::Services::CurrentBusinessDate.call

        Models::DepositAccount.transaction do
          account = Models::DepositAccount.create!(
            account_number: generate_account_number,
            currency: "USD",
            status: Models::DepositAccount::STATUS_OPEN,
            product_code: Accounts::SLICE1_PRODUCT_CODE
          )

          Models::DepositAccountParty.create!(
            deposit_account: account,
            party_record_id: party_record_id,
            role: Models::DepositAccountParty::ROLE_OWNER,
            status: Models::DepositAccountParty::STATUS_ACTIVE,
            effective_on: on_date,
            ended_on: nil
          )

          account.reload
        end
      end

      def self.generate_account_number
        "DA#{SecureRandom.hex(8).upcase}"
      end
      private_class_method :generate_account_number
    end
  end
end
