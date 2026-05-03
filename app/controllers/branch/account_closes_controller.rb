# frozen_string_literal: true

module Branch
  class AccountClosesController < ApplicationController
    before_action :load_account_context
    before_action :require_account_maintain_capability!

    def new
      @account_close = default_close_params
    end

    def create
      @account_close = close_params.with_indifferent_access
      result = Accounts::Commands::CloseAccount.call(
        deposit_account_id: @account.id,
        reason_code: @account_close[:reason_code],
        reason_description: @account_close[:reason_description],
        effective_on: @account_close[:effective_on],
        idempotency_key: @account_close[:idempotency_key],
        actor_id: current_operator.id,
        channel: branch_channel
      )
      redirect_to branch_servicing_deposit_account_path(@account),
        notice: result[:outcome] == :replay ? "Account close already recorded." : "Account closed."
    rescue Accounts::Commands::CloseAccount::InvalidRequest => e
      @error_message = e.message
      render :new, status: :unprocessable_entity
    end

    private

    def load_account_context
      load_account_context!(deposit_account_id: params[:deposit_account_id])
    end

    def require_account_maintain_capability!
      require_branch_capability!(Workspace::Authorization::CapabilityRegistry::ACCOUNT_MAINTAIN)
    end

    def default_close_params
      {
        "reason_code" => nil,
        "reason_description" => nil,
        "effective_on" => Core::BusinessDate::Services::CurrentBusinessDate.call,
        "idempotency_key" => default_idempotency_key("branch-account-close")
      }
    rescue Core::BusinessDate::Errors::NotSet
      {
        "reason_code" => nil,
        "reason_description" => nil,
        "effective_on" => Date.current,
        "idempotency_key" => default_idempotency_key("branch-account-close")
      }
    end

    def close_params
      params.require(:account_close).permit(
        :reason_code,
        :reason_description,
        :effective_on,
        :idempotency_key
      ).to_h
    end
  end
end
