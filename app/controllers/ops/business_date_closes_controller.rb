# frozen_string_literal: true

module Ops
  class BusinessDateClosesController < ApplicationController
    def new
      @business_date = resolve_business_date
      load_preview if @business_date
    end

    def create
      @business_date = resolve_business_date
      return render :new, status: :unprocessable_entity if @business_date.nil?

      result = Core::BusinessDate::Commands::CloseBusinessDate.call(
        closed_by_operator_id: current_operator.id,
        business_date: @business_date
      )
      redirect_to ops_business_date_close_path,
        notice: "Closed #{result[:closed_on].iso8601}; current business date is #{result[:setting].current_business_on.iso8601}."
    rescue Core::BusinessDate::Errors::EodNotReady => e
      @error_message = e.message
      @readiness = e.readiness if e.respond_to?(:readiness)
      render :new, status: :unprocessable_entity
    rescue Core::BusinessDate::Errors::NotSet, ArgumentError => e
      @error_message = e.message
      render :new, status: :unprocessable_entity
    end

    private

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
    rescue Core::BusinessDate::Errors::NotSet => e
      @error_message = e.message
    end
  end
end
