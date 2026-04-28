# frozen_string_literal: true

module Branch
  class AccountPartiesController < ApplicationController
    before_action :load_account
    before_action :require_account_maintain_capability!

    def new_authorized_signer
      @authorized_signer = default_add_params
    end

    def create_authorized_signer
      @authorized_signer = add_params.with_indifferent_access
      result = Accounts::Commands::AddAuthorizedSigner.call(
        deposit_account_id: @account.id,
        party_record_id: @authorized_signer[:party_record_id].to_i,
        channel: branch_channel,
        idempotency_key: @authorized_signer[:idempotency_key],
        actor_id: current_operator.id,
        effective_on: @authorized_signer[:effective_on]
      )
      render_result(result)
    rescue Accounts::Commands::AddAuthorizedSigner::InvalidRequest => e
      @error_message = e.message
      render :new_authorized_signer, status: :unprocessable_entity
    end

    def end_authorized_signer
      @relationship = load_relationship
      @authorized_signer_end = default_end_params
    end

    def create_end_authorized_signer
      @relationship = load_relationship
      @authorized_signer_end = end_params.with_indifferent_access
      result = Accounts::Commands::EndAuthorizedSigner.call(
        deposit_account_party_id: @relationship.id,
        channel: branch_channel,
        idempotency_key: @authorized_signer_end[:idempotency_key],
        actor_id: current_operator.id,
        ended_on: @authorized_signer_end[:ended_on]
      )
      render_result(result)
    rescue Accounts::Commands::EndAuthorizedSigner::InvalidRequest => e
      @error_message = e.message
      @relationship ||= Accounts::Models::DepositAccountParty.find_by(id: params[:relationship_id])
      if @relationship.nil?
        redirect_to branch_servicing_deposit_account_path(@account), alert: @error_message
        return
      end
      @authorized_signer_end ||= default_end_params
      render :end_authorized_signer, status: :unprocessable_entity
    end

    private

    def require_account_maintain_capability!
      require_branch_capability!(Workspace::Authorization::CapabilityRegistry::ACCOUNT_MAINTAIN)
    end

    def load_account
      @account = Accounts::Models::DepositAccount.find(params[:deposit_account_id])
    end

    def load_relationship
      Accounts::Models::DepositAccountParty
        .includes(:party_record)
        .where(deposit_account_id: @account.id)
        .find(params[:relationship_id])
    end

    def default_add_params
      {
        "party_record_id" => params[:party_record_id],
        "effective_on" => current_business_date,
        "idempotency_key" => default_idempotency_key("branch-authorized-signer-add")
      }
    end

    def default_end_params
      {
        "ended_on" => current_business_date,
        "idempotency_key" => default_idempotency_key("branch-authorized-signer-end")
      }
    end

    def current_business_date
      Core::BusinessDate::Services::CurrentBusinessDate.call
    rescue Core::BusinessDate::Errors::NotSet
      Date.current
    end

    def add_params
      params.require(:authorized_signer).permit(:party_record_id, :effective_on, :idempotency_key).to_h
    end

    def end_params
      params.require(:authorized_signer_end).permit(:ended_on, :idempotency_key).to_h
    end

    def render_result(result)
      @audit = result[:audit]
      @relationship = result[:relationship]
      @outcome = result[:outcome]
      render :result, status: @outcome == :created ? :created : :ok
    end
  end
end
