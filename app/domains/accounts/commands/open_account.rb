# frozen_string_literal: true

module Accounts
  module Commands
    class OpenAccount
      class PartyNotFound < StandardError; end
      class JointPartyNotFound < StandardError; end
      class InvalidJointParty < StandardError; end
      class ProductNotFound < StandardError; end
      class ProductConflict < StandardError; end

      # @param party_record_id [Integer] primary owner
      # @param joint_party_record_id [Integer, nil] optional second party (joint_owner)
      # @param effective_on [Date, nil] defaults to Core::BusinessDate
      # @param deposit_product_id [Integer, nil] FK to deposit_products (optional)
      # @param product_code [String, nil] must match deposit_product when both given
      def self.call(party_record_id:, joint_party_record_id: nil, effective_on: nil, deposit_product_id: nil, product_code: nil)
        begin
          Party::Queries::FindParty.by_id(party_record_id)
        rescue ActiveRecord::RecordNotFound
          raise PartyNotFound, "party_record_id=#{party_record_id} not found"
        end

        if joint_party_record_id.present?
          jid = joint_party_record_id.to_i
          raise InvalidJointParty, "joint_party_record_id must differ from party_record_id" if jid == party_record_id.to_i

          begin
            Party::Queries::FindParty.by_id(jid)
          rescue ActiveRecord::RecordNotFound
            raise JointPartyNotFound, "joint_party_record_id=#{jid} not found"
          end
        end

        deposit_product = resolve_deposit_product!(deposit_product_id: deposit_product_id, product_code: product_code)
        on_date = effective_on || Core::BusinessDate::Services::CurrentBusinessDate.call

        Models::DepositAccount.transaction do
          account = Models::DepositAccount.create!(
            account_number: Accounts::Services::DepositAccountNumberGenerator.call(on_date: on_date),
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

          if joint_party_record_id.present?
            Models::DepositAccountParty.create!(
              deposit_account: account,
              party_record_id: joint_party_record_id.to_i,
              role: Models::DepositAccountParty::ROLE_JOINT_OWNER,
              status: Models::DepositAccountParty::STATUS_ACTIVE,
              effective_on: on_date,
              ended_on: nil
            )
          end

          Models::DepositAccountBalanceProjection.create!(
            deposit_account: account,
            as_of_business_date: on_date,
            last_calculated_at: Time.current,
            calculation_version: Models::DepositAccountBalanceProjection::CURRENT_CALCULATION_VERSION
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
    end
  end
end
