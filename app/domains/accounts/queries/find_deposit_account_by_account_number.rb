# frozen_string_literal: true

module Accounts
  module Queries
    class FindDepositAccountByAccountNumber
      class InvalidAccountNumber < StandardError; end

      def self.call(account_number:)
        normalized = normalize_account_number(account_number)
        Models::DepositAccount.find_by(account_number: normalized)
      end

      def self.open(account_number:)
        account = call(account_number: account_number)
        return nil unless account&.status == Models::DepositAccount::STATUS_OPEN

        account
      end

      def self.normalize_account_number(account_number)
        normalized = account_number.to_s.strip
        raise InvalidAccountNumber, "account_number is required" if normalized.blank?

        normalized
      end
      private_class_method :normalize_account_number
    end
  end
end
