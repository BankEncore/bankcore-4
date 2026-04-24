# frozen_string_literal: true

module Products
  module Queries
    class FindDepositProduct
      def self.default_slice1!
        row = Models::DepositProduct.find_by(product_code: Accounts::SLICE1_PRODUCT_CODE)
        raise ActiveRecord::RecordNotFound, "missing deposit_product #{Accounts::SLICE1_PRODUCT_CODE}" if row.nil?

        row
      end

      def self.by_id!(id)
        Models::DepositProduct.find(id)
      end

      def self.by_code!(code)
        Models::DepositProduct.find_by!(product_code: code.to_s)
      end
    end
  end
end
