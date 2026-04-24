# frozen_string_literal: true

module BankCore
  module Seeds
    module DepositProducts
      # Idempotent seed for development and test (migration also inserts slice-1 row for existing DBs).
      def self.seed!
        Products::Models::DepositProduct.find_or_create_by!(product_code: Accounts::SLICE1_PRODUCT_CODE) do |p|
          p.name = "Slice 1 demand deposit (seeded)"
          p.status = Products::Models::DepositProduct::STATUS_ACTIVE
          p.currency = "USD"
        end
      end
    end
  end
end
