# frozen_string_literal: true

module Ops
  class EodController < ApplicationController
    def index
      @business_date = resolve_business_date
      return if @business_date.nil?

      @readiness = Teller::Queries::EodReadiness.call(business_date: @business_date)
      @trial_balance_rows = Core::Ledger::Queries::TrialBalanceForBusinessDate.call(business_date: @business_date)
    rescue Core::BusinessDate::Errors::NotSet => e
      @error_message = e.message
      render :index, status: :unprocessable_entity
    end

    private

    def resolve_business_date
      raw = params[:business_date].presence
      date = raw.present? ? Date.iso8601(raw.to_s) : Core::BusinessDate::Services::CurrentBusinessDate.call
      current = Core::BusinessDate::Services::CurrentBusinessDate.call
      if date > current
        @error_message = "business_date cannot be after current business date"
        render :index, status: :unprocessable_entity
        return nil
      end

      date
    rescue ArgumentError, TypeError
      @error_message = "business_date must be a valid ISO 8601 date (YYYY-MM-DD)"
      render :index, status: :unprocessable_entity
      nil
    end
  end
end
