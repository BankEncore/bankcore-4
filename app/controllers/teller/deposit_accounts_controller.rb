# frozen_string_literal: true

module Teller
  class DepositAccountsController < ApplicationController
    def create
      attrs = params.require(:deposit_account).permit(
        :party_record_id, :deposit_product_id, :product_code
      ).to_h.symbolize_keys
      party_record_id = attrs[:party_record_id].to_i
      deposit_product_id = attrs[:deposit_product_id].presence&.to_i
      product_code = attrs[:product_code].presence

      account = Accounts::Commands::OpenAccount.call(
        party_record_id: party_record_id,
        deposit_product_id: deposit_product_id,
        product_code: product_code
      )
      render json: {
        id: account.id,
        account_number: account.account_number,
        deposit_product_id: account.deposit_product_id,
        product_code: account.product_code,
        product_name: account.deposit_product.name,
        status: account.status
      }, status: :created
    rescue Accounts::Commands::OpenAccount::PartyNotFound
      render json: { error: "party_not_found" }, status: :not_found
    rescue Accounts::Commands::OpenAccount::ProductNotFound
      render json: { error: "product_not_found" }, status: :not_found
    rescue Accounts::Commands::OpenAccount::ProductConflict
      render json: { error: "product_conflict", message: "deposit_product_id and product_code disagree" },
        status: :unprocessable_entity
    rescue Core::BusinessDate::Errors::NotSet
      render json: { error: "business_date_not_set" }, status: :unprocessable_entity
    end
  end
end
