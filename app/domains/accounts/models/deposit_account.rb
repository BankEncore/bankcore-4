# frozen_string_literal: true

module Accounts
  module Models
    class DepositAccount < ApplicationRecord
      self.table_name = "deposit_accounts"

      STATUS_OPEN = "open"
      STATUS_CLOSED = "closed"

      has_many :deposit_account_parties, class_name: "Accounts::Models::DepositAccountParty", dependent: :restrict_with_exception,
        inverse_of: :deposit_account

      belongs_to :deposit_product, class_name: "Products::Models::DepositProduct"

      validates :account_number, presence: true, uniqueness: true
      validates :currency, presence: true
      validates :status, presence: true, inclusion: { in: [ STATUS_OPEN, STATUS_CLOSED ] }
      validates :product_code, presence: true
      validate :product_code_matches_deposit_product

      private

      def product_code_matches_deposit_product
        return if deposit_product.nil?

        errors.add(:product_code, "must match deposit_product.product_code") if product_code != deposit_product.product_code
      end
    end
  end
end
