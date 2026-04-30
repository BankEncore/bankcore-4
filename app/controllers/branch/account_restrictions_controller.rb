# frozen_string_literal: true

module Branch
  class AccountRestrictionsController < ApplicationController
    before_action :load_account
    before_action :require_account_maintain_capability!

    def new
      @restriction = default_restriction_params
    end

    def create
      @restriction = restriction_params.with_indifferent_access
      result = Accounts::Commands::RestrictAccount.call(
        deposit_account_id: @account.id,
        restriction_type: @restriction[:restriction_type],
        reason_code: @restriction[:reason_code],
        reason_description: @restriction[:reason_description],
        effective_on: @restriction[:effective_on],
        idempotency_key: @restriction[:idempotency_key],
        actor_id: current_operator.id,
        channel: branch_channel
      )
      redirect_to branch_servicing_deposit_account_path(@account),
        notice: result[:outcome] == :replay ? "Account restriction already recorded." : "Account restriction recorded."
    rescue Accounts::Commands::RestrictAccount::InvalidRequest => e
      @error_message = e.message
      render :new, status: :unprocessable_entity
    end

    def release
      restriction = @account.account_restrictions.find(params[:id])
      result = Accounts::Commands::UnrestrictAccount.call(
        account_restriction_id: restriction.id,
        released_on: params[:released_on],
        idempotency_key: params[:idempotency_key].presence || default_idempotency_key("branch-account-unrestriction"),
        actor_id: current_operator.id,
        channel: branch_channel
      )
      redirect_to branch_servicing_deposit_account_path(@account),
        notice: result[:outcome] == :replay ? "Account restriction release already recorded." : "Account restriction released."
    rescue Accounts::Commands::UnrestrictAccount::InvalidRequest => e
      redirect_to branch_servicing_deposit_account_path(@account), alert: e.message
    end

    private

    def load_account
      @account = Accounts::Models::DepositAccount.find(params[:deposit_account_id])
    end

    def require_account_maintain_capability!
      require_branch_capability!(Workspace::Authorization::CapabilityRegistry::ACCOUNT_MAINTAIN)
    end

    def default_restriction_params
      {
        "restriction_type" => Accounts::Models::AccountRestriction::TYPE_WATCH_ONLY,
        "reason_code" => nil,
        "reason_description" => nil,
        "effective_on" => Core::BusinessDate::Services::CurrentBusinessDate.call,
        "idempotency_key" => default_idempotency_key("branch-account-restriction")
      }
    rescue Core::BusinessDate::Errors::NotSet
      {
        "restriction_type" => Accounts::Models::AccountRestriction::TYPE_WATCH_ONLY,
        "reason_code" => nil,
        "reason_description" => nil,
        "effective_on" => Date.current,
        "idempotency_key" => default_idempotency_key("branch-account-restriction")
      }
    end

    def restriction_params
      params.require(:restriction).permit(
        :restriction_type,
        :reason_code,
        :reason_description,
        :effective_on,
        :idempotency_key
      ).to_h
    end
  end
end
