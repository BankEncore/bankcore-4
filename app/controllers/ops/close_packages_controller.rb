# frozen_string_literal: true

module Ops
  class ClosePackagesController < ApplicationController
    def show
      @business_date = resolve_business_date
      return if @business_date.nil?

      @current_business_date = Core::BusinessDate::Services::CurrentBusinessDate.call
      @classification = Teller::Queries::ClosePackageClassification.call(business_date: @business_date)
      @readiness = @classification[:readiness]
      @trial_balance_rows = Core::Ledger::Queries::TrialBalanceForBusinessDate.call(business_date: @business_date)
      @close_event = Core::BusinessDate::Models::BusinessDateCloseEvent
        .includes(:closed_by_operator)
        .find_by(closed_on: @business_date)
      @posting_day_closed = @readiness[:posting_day_closed]
      @balance_projection_health = load_balance_projection_health_if_current_day

      event_scope = Core::OperationalEvents::Models::OperationalEvent.where(business_date: @business_date)
      @event_total_count = event_scope.count
      @event_status_counts = event_scope.group(:status).count.sort.to_h
      @event_channel_counts = event_scope.group(:channel).count.sort.to_h
      @event_type_counts = event_scope.group(:event_type).count.sort.to_h
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

      @embedded_close_section = @classification[:actionable_close_package]
    rescue Core::BusinessDate::Errors::NotSet => e
      @error_message = e.message
      render :show, status: :unprocessable_entity
    end

    private

    def load_balance_projection_health_if_current_day
      return nil unless @business_date == @current_business_date

      Accounts::Queries::DepositBalanceProjectionHealth.call
    end

    def resolve_business_date
      raw = params[:business_date].presence
      date = raw.present? ? Date.iso8601(raw.to_s) : Core::BusinessDate::Services::CurrentBusinessDate.call
      current = Core::BusinessDate::Services::CurrentBusinessDate.call
      if date > current
        @error_message = "business_date cannot be after current business date"
        render :show, status: :unprocessable_entity
        return nil
      end

      date
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
