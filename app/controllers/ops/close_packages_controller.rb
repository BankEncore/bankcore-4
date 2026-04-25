# frozen_string_literal: true

module Ops
  class ClosePackagesController < ApplicationController
    def show
      @business_date = resolve_business_date
      return if @business_date.nil?

      @readiness = Teller::Queries::EodReadiness.call(business_date: @business_date)
      @trial_balance_rows = Core::Ledger::Queries::TrialBalanceForBusinessDate.call(business_date: @business_date)
      @pending_events = Core::OperationalEvents::Models::OperationalEvent
        .where(business_date: @business_date, status: Core::OperationalEvents::Models::OperationalEvent::STATUS_PENDING)
        .order(:id)
      @open_or_pending_sessions = Teller::Models::TellerSession
        .where(status: [ Teller::Models::TellerSession::STATUS_OPEN, Teller::Models::TellerSession::STATUS_PENDING_SUPERVISOR ])
        .order(:opened_at, :id)
      @recent_closes = Core::BusinessDate::Models::BusinessDateCloseEvent
        .includes(:closed_by_operator)
        .order(closed_at: :desc, id: :desc)
        .limit(10)
    rescue Core::BusinessDate::Errors::NotSet => e
      @error_message = e.message
      render :show, status: :unprocessable_entity
    end

    private

    def resolve_business_date
      raw = params[:business_date].presence
      raw.present? ? Date.iso8601(raw.to_s) : Core::BusinessDate::Services::CurrentBusinessDate.call
    rescue ArgumentError, TypeError
      @error_message = "business_date must be a valid ISO 8601 date (YYYY-MM-DD)"
      render :show, status: :unprocessable_entity
      nil
    rescue Core::BusinessDate::Errors::NotSet => e
      @error_message = e.message
      render :show, status: :unprocessable_entity
      nil
    end
  end
end
