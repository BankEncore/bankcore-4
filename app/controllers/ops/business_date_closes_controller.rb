# frozen_string_literal: true

module Ops
  class BusinessDateClosesController < ApplicationController
    def new
      @business_date = resolve_business_date
      load_preview if @business_date
    end

    def create
      submitted_raw = params[:business_date].presence || params.dig(:business_date_close, :business_date).presence
      @business_date = resolve_business_date
      if @business_date.nil?
        redirect_path = close_package_redirect_path(submitted_raw)
        return redirect_to redirect_path, alert: @error_message.presence || "Unable to close business date."
      end

      result = Core::BusinessDate::Commands::CloseBusinessDate.call(
        closed_by_operator_id: current_operator.id,
        business_date: @business_date
      )
      redirect_to ops_close_package_path,
        notice: "Closed #{result[:closed_on].iso8601}; current business date is #{result[:setting].current_business_on.iso8601}."
    rescue Core::BusinessDate::Errors::EodNotReady => e
      redirect_to ops_close_package_path(business_date: @business_date.iso8601), alert: e.message
    rescue Core::BusinessDate::Errors::NotSet, ArgumentError => e
      redirect_to close_package_redirect_path(submitted_raw.presence || @business_date&.iso8601), alert: e.message
    rescue Workspace::Authorization::Forbidden => e
      redirect_to ops_close_package_path(business_date: @business_date.iso8601), alert: e.message
    end

    private

    def close_package_redirect_path(raw_date)
      return ops_close_package_path if raw_date.blank?

      ops_close_package_path(business_date: raw_date.to_s)
    end

    def resolve_business_date
      raw = params[:business_date].presence || params.dig(:business_date_close, :business_date).presence
      return Core::BusinessDate::Services::CurrentBusinessDate.call if raw.blank?

      Date.iso8601(raw.to_s)
    rescue ArgumentError, TypeError
      @error_message = "business_date must be a valid ISO 8601 date (YYYY-MM-DD)"
      nil
    rescue Core::BusinessDate::Errors::NotSet => e
      @error_message = e.message
      nil
    end

    def load_preview
      @readiness = Teller::Queries::EodReadiness.call(business_date: @business_date)
      @trial_balance_rows = Core::Ledger::Queries::TrialBalanceForBusinessDate.call(business_date: @business_date)
      @balance_projection_health = Accounts::Queries::DepositBalanceProjectionHealth.call
    rescue Core::BusinessDate::Errors::NotSet => e
      @error_message = e.message
    end
  end
end
