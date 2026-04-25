# frozen_string_literal: true

module Branch
  class DepositAccountsController < ApplicationController
    def new
      @deposit_account = {
        "party_record_id" => params[:party_record_id],
        "joint_party_record_id" => nil,
        "deposit_product_id" => nil,
        "product_code" => nil
      }
    end

    def create
      @deposit_account = deposit_account_params
      account = Accounts::Commands::OpenAccount.call(
        party_record_id: @deposit_account[:party_record_id].to_i,
        joint_party_record_id: parse_optional_integer(@deposit_account[:joint_party_record_id]),
        deposit_product_id: parse_optional_integer(@deposit_account[:deposit_product_id]),
        product_code: @deposit_account[:product_code].presence
      )
      redirect_to new_branch_deposit_path(deposit_account_id: account.id),
        notice: "Opened deposit account ##{account.id} (#{account.account_number}). Record an initial deposit next."
    rescue Accounts::Commands::OpenAccount::PartyNotFound => e
      render_error(e.message.presence || "Party not found")
    rescue Accounts::Commands::OpenAccount::JointPartyNotFound => e
      render_error(e.message.presence || "Joint party not found")
    rescue Accounts::Commands::OpenAccount::InvalidJointParty => e
      render_error(e.message.presence || "Joint party must differ from primary party")
    rescue Accounts::Commands::OpenAccount::ProductNotFound => e
      render_error(e.message.presence || "Deposit product not found")
    rescue Accounts::Commands::OpenAccount::ProductConflict => e
      render_error(e.message.presence || "Deposit product id and product code disagree")
    rescue Core::BusinessDate::Errors::NotSet => e
      render_error(e.message)
    end

    private

    def deposit_account_params
      params.require(:deposit_account).permit(
        :party_record_id, :joint_party_record_id, :deposit_product_id, :product_code
      ).to_h.symbolize_keys
    end

    def render_error(message)
      @error_message = message
      render :new, status: :unprocessable_entity
    end
  end
end
