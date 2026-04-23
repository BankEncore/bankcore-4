# frozen_string_literal: true

module Teller
  class ReportsController < ApplicationController
    def trial_balance
      date = resolve_business_date!
      return if performed?

      rows = Core::Ledger::Queries::TrialBalanceForBusinessDate.call(business_date: date)
      render json: {
        business_date: date.iso8601,
        rows: rows.map { |r| trial_balance_row_json(r) }
      }
    end

    def eod_readiness
      date = resolve_business_date!
      return if performed?

      render json: Teller::Queries::EodReadiness.call(business_date: date)
    end

    private

    def trial_balance_row_json(row)
      {
        gl_account_id: row.gl_account_id,
        account_number: row.account_number,
        account_name: row.account_name,
        account_type: row.account_type,
        debit_minor_units: row.debit_minor_units,
        credit_minor_units: row.credit_minor_units
      }
    end

    def resolve_business_date!
      raw = params[:business_date].presence
      date =
        if raw.blank?
          Core::BusinessDate::Services::CurrentBusinessDate.call
        else
          Date.iso8601(raw)
        end

      current = Core::BusinessDate::Services::CurrentBusinessDate.call
      if date > current
        render json: { error: "invalid_request", message: "business_date cannot be after current business date" },
          status: :unprocessable_entity
        return nil
      end

      date
    rescue ArgumentError, TypeError
      render json: { error: "invalid_request", message: "business_date must be a valid ISO 8601 date (YYYY-MM-DD)" },
        status: :unprocessable_entity
      nil
    end
  end
end
