# frozen_string_literal: true

module Branch
  class ServicingDepositAccountsController < ApplicationController
    RECENT_ACTIVITY_DAYS = 30

    def show
      @profile = Accounts::Queries::DepositAccountProfile.call(deposit_account_id: params[:id])
      @account = @profile.account
      @holds = Accounts::Queries::ListHoldsForAccount.call(deposit_account_id: @account.id, limit: 10)
      @statements = Deposits::Queries::ListDepositStatements.call(deposit_account_id: @account.id, limit: 5)
      @activity = Deposits::Queries::StatementActivity.call(
        deposit_account_id: @account.id,
        period_start_on: activity_start_on,
        period_end_on: activity_end_on
      )
      @events = Core::OperationalEvents::Queries::ListOperationalEvents.call(
        business_date_from: activity_start_on,
        business_date_to: activity_end_on,
        source_account_id: @account.id,
        limit: 10
      )
      @can_place_holds = can_place_servicing_hold?
      @can_release_holds = can_release_servicing_hold?
      @can_waive_fees = can_waive_fee?
      @can_reverse_events = can_reverse_event?
    rescue Core::OperationalEvents::Queries::ListOperationalEvents::InvalidQuery => e
      redirect_to branch_path, alert: e.message
    end

    private

    def activity_end_on
      @activity_end_on ||= @profile.current_business_date || Date.current
    end

    def activity_start_on
      @activity_start_on ||= activity_end_on - RECENT_ACTIVITY_DAYS
    end
  end
end
