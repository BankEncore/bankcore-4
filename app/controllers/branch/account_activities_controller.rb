# frozen_string_literal: true

module Branch
  class AccountActivitiesController < ApplicationController
    DEFAULT_SPAN_DAYS = 30

    def show
      @account = Accounts::Models::DepositAccount.find(params[:deposit_account_id])
      @period_start_on, @period_end_on = activity_range
      @activity = Deposits::Queries::StatementActivity.call(
        deposit_account_id: @account.id,
        period_start_on: @period_start_on,
        period_end_on: @period_end_on
      )
      @events = Core::OperationalEvents::Queries::ListOperationalEvents.call(
        business_date_from: @period_start_on,
        business_date_to: @period_end_on,
        source_account_id: @account.id,
        limit: 50
      )
    rescue ArgumentError, Core::OperationalEvents::Queries::ListOperationalEvents::InvalidQuery => e
      @error_message = e.message
      @activity = nil
      @events = nil
      render :show, status: :unprocessable_entity
    end

    private

    def activity_range
      current = Core::BusinessDate::Services::CurrentBusinessDate.call
      end_on = params[:period_end_on].present? ? Date.iso8601(params[:period_end_on].to_s) : current
      start_on = params[:period_start_on].present? ? Date.iso8601(params[:period_start_on].to_s) : end_on - DEFAULT_SPAN_DAYS
      [ start_on, end_on ]
    end
  end
end
