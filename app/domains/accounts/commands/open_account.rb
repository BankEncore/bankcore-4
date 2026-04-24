# frozen_string_literal: true

module Accounts
  module Commands
    class OpenAccount
      class PartyNotFound < StandardError; end
      class ProductNotFound < StandardError; end
      class ProductConflict < StandardError; end

      # @param party_record_id [Integer]
      # @param effective_on [Date, nil] defaults to Core::BusinessDate
      # @param deposit_product_id [Integer, nil] FK to deposit_products (optional)
      # @param product_code [String, nil] must match deposit_product when both given
      def self.call(party_record_id:, effective_on: nil, deposit_product_id: nil, product_code: nil)
        begin
          Party::Queries::FindParty.by_id(party_record_id)
        rescue ActiveRecord::RecordNotFound
          raise PartyNotFound, "party_record_id=#{party_record_id} not found"
        end

        deposit_product = resolve_deposit_product!(deposit_product_id: deposit_product_id, product_code: product_code)
        on_date = effective_on || Core::BusinessDate::Services::CurrentBusinessDate.call

        Models::DepositAccount.transaction do
          account = Models::DepositAccount.create!(
            account_number: generate_account_number,
            currency: deposit_product.currency,
            status: Models::DepositAccount::STATUS_OPEN,
            deposit_product: deposit_product,
            product_code: deposit_product.product_code
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

      def self.resolve_deposit_product!(deposit_product_id:, product_code:)
        if deposit_product_id.present? && product_code.present?
          p = Products::Queries::FindDepositProduct.by_id!(deposit_product_id)
          raise ProductConflict, "product_code does not match deposit_product" unless p.product_code == product_code.to_s

          p
        elsif deposit_product_id.present?
          Products::Queries::FindDepositProduct.by_id!(deposit_product_id)
        elsif product_code.present?
          Products::Queries::FindDepositProduct.by_code!(product_code)
        else
          Products::Queries::FindDepositProduct.default_slice1!
        end
      rescue ActiveRecord::RecordNotFound => e
        raise ProductNotFound, e.message
      end
      private_class_method :resolve_deposit_product!

      def self.generate_account_number
        "DA#{SecureRandom.hex(8).upcase}"
      end
      private_class_method :generate_account_number
    end
  end
end
