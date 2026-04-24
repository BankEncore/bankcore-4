# frozen_string_literal: true

module Products
  module Models
    class DepositProduct < ApplicationRecord
      self.table_name = "deposit_products"

      STATUS_ACTIVE = "active"
      STATUS_INACTIVE = "inactive"

      has_many :deposit_accounts, class_name: "Accounts::Models::DepositAccount",
                                    inverse_of: :deposit_product,
                                    dependent: :restrict_with_exception
      has_many :deposit_product_fee_rules, class_name: "Products::Models::DepositProductFeeRule",
                                           inverse_of: :deposit_product,
                                           dependent: :restrict_with_exception

      validates :product_code, presence: true, uniqueness: true
      validates :name, presence: true
      validates :status, presence: true, inclusion: { in: [ STATUS_ACTIVE, STATUS_INACTIVE ] }
      validates :currency, presence: true
    end
  end
end
