# frozen_string_literal: true

module Teller
  class BusinessDateClosesController < ApplicationController
    before_action :require_business_date_close_capability!

    def create
      optional_date = parse_optional_business_date
      return if performed?

      result = Core::BusinessDate::Commands::CloseBusinessDate.call(
        closed_by_operator_id: current_operator.id,
        business_date: optional_date
      )
      setting = result[:setting]
      render json: {
        closed_on: result[:closed_on].iso8601,
        previous_business_on: result[:previous_business_on].iso8601,
        current_business_on: setting.current_business_on.iso8601
      }, status: :created
    rescue Core::BusinessDate::Errors::EodNotReady => e
      body = { error: "eod_not_ready", message: e.message }
      body.merge!(e.readiness) if e.readiness.is_a?(Hash)
      render json: body, status: :unprocessable_entity
    rescue Core::BusinessDate::Errors::NotSet => e
      render json: { error: "business_date_not_set", message: e.message }, status: :unprocessable_entity
    rescue Workspace::Authorization::Forbidden
      render json: { error: "forbidden", message: "supervisor role required" }, status: :forbidden
    rescue ArgumentError => e
      render json: { error: "invalid_request", message: e.message }, status: :unprocessable_entity
    end

    private

    def require_business_date_close_capability!
      require_capability!(Workspace::Authorization::CapabilityRegistry::BUSINESS_DATE_CLOSE)
    end

    def parse_optional_business_date
      raw = params[:business_date].presence || params.dig(:business_date_close, :business_date).presence
      return nil if raw.blank?

      Date.iso8601(raw.to_s)
    rescue ArgumentError, TypeError
      render json: { error: "invalid_request", message: "business_date must be a valid ISO 8601 date (YYYY-MM-DD)" },
        status: :unprocessable_entity
      nil
    end
  end
end
