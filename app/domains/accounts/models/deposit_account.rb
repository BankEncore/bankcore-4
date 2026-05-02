# frozen_string_literal: true

module Accounts
  module Models
    class DepositAccount < ApplicationRecord
      self.table_name = "deposit_accounts"

      STATUS_OPEN = "open"
      STATUS_CLOSED = "closed"

      has_many :deposit_account_parties, class_name: "Accounts::Models::DepositAccountParty", dependent: :restrict_with_exception,
        inverse_of: :deposit_account
      has_many :account_restrictions, class_name: "Accounts::Models::AccountRestriction", dependent: :restrict_with_exception
      has_many :account_lifecycle_events, class_name: "Accounts::Models::AccountLifecycleEvent", dependent: :restrict_with_exception

      belongs_to :deposit_product, class_name: "Products::Models::DepositProduct"
      has_many :deposit_statements, class_name: "Deposits::Models::DepositStatement",
                                    inverse_of: :deposit_account,
                                    dependent: :restrict_with_exception

      validates :account_number, presence: true, uniqueness: true,
        format: { with: /\A1\d{11}\z/, message: "must be a 12-digit deposit account number" }
      validate :account_number_luhn_check_digit
      validates :currency, presence: true
      validates :status, presence: true, inclusion: { in: [ STATUS_OPEN, STATUS_CLOSED ] }
      validates :product_code, presence: true
      validate :product_code_matches_deposit_product

      private

      def product_code_matches_deposit_product
        return if deposit_product.nil?

        errors.add(:product_code, "must match deposit_product.product_code") if product_code != deposit_product.product_code
      end

      def account_number_luhn_check_digit
        return if account_number.blank?
        return if Accounts::Services::DepositAccountNumberGenerator.valid_luhn?(account_number)

        errors.add(:account_number, "has an invalid check digit")
      end
    end
  end
end
