# frozen_string_literal: true

module Ops
  class EngineRunsController < ApplicationController
    ENGINES = %w[monthly_maintenance_fees deposit_statements].freeze

    def index
      @business_date = current_business_date
    end

    def new
      @engine = permitted_engine
      @business_date = resolve_business_date
      @deposit_product_id = params[:deposit_product_id].presence
      @account_ids = parse_account_ids(params[:account_ids])
      return if @error_message.present?

      @result = run_engine(preview: true)
    end

    def create
      @engine = permitted_engine
      @business_date = resolve_business_date
      @deposit_product_id = params.dig(:engine_run, :deposit_product_id).presence
      @account_ids = parse_account_ids(params.dig(:engine_run, :account_ids))
      return render :new, status: :unprocessable_entity if @error_message.present?

      @result = run_engine(preview: false)
      render :show, status: :created
    rescue Accounts::Commands::AssessMonthlyMaintenanceFees::InvalidRequest => e
      @error_message = e.message
      render :new, status: :unprocessable_entity
    end

    private

    def permitted_engine
      engine = params[:engine].to_s
      raise ActionController::RoutingError, "unknown engine" unless ENGINES.include?(engine)

      engine
    end

    def resolve_business_date
      raw = params[:business_date].presence || params.dig(:engine_run, :business_date).presence
      return Core::BusinessDate::Services::CurrentBusinessDate.call if raw.blank?

      Date.iso8601(raw.to_s)
    rescue ArgumentError, TypeError
      @error_message = "business_date must be a valid ISO 8601 date (YYYY-MM-DD)"
      nil
    rescue Core::BusinessDate::Errors::NotSet => e
      @error_message = e.message
      nil
    end

    def parse_account_ids(raw)
      return nil if raw.blank?

      raw.to_s.split(/[,\s]+/).reject(&:blank?).map { |value| Integer(value) }
    rescue ArgumentError, TypeError
      @error_message = "account_ids must be integers separated by commas or spaces"
      nil
    end

    def run_engine(preview:)
      case @engine
      when "monthly_maintenance_fees"
        Accounts::Commands::AssessMonthlyMaintenanceFees.call(
          business_date: @business_date,
          deposit_product_id: @deposit_product_id,
          account_ids: @account_ids,
          preview: preview
        )
      when "deposit_statements"
        Deposits::Commands::GenerateDepositStatements.call(
          business_date: @business_date,
          deposit_product_id: @deposit_product_id,
          account_ids: @account_ids,
          preview: preview
        )
      end
    end
  end
end
