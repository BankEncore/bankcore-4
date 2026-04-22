# frozen_string_literal: true

module Teller
  class DepositAccountsController < ApplicationController
    def create
      party_record_id = params.require(:deposit_account).permit(:party_record_id).fetch(:party_record_id).to_i
      account = Accounts::Commands::OpenAccount.call(party_record_id: party_record_id)
      render json: {
        id: account.id,
        account_number: account.account_number,
        product_code: account.product_code,
        status: account.status
      }, status: :created
    rescue Accounts::Commands::OpenAccount::PartyNotFound
      render json: { error: "party_not_found" }, status: :not_found
    rescue Core::BusinessDate::Errors::NotSet
      render json: { error: "business_date_not_set" }, status: :unprocessable_entity
    end
  end
end
