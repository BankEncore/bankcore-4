# frozen_string_literal: true

module Admin
  class CashLocationsController < ApplicationController
    before_action -> { require_admin_capability!(Workspace::Authorization::CapabilityRegistry::SYSTEM_CONFIGURE) }
    before_action :load_cash_location, only: %i[show edit update deactivate]
    before_action :load_form_options, only: %i[new create edit update show]

    def index
      @operating_unit_id = params[:operating_unit_id].presence
      @location_type = params[:location_type].presence
      @status = params[:status].presence
      @cash_locations = Cash::Queries::LocationDirectory.call(
        operating_unit_id: @operating_unit_id,
        location_type: @location_type,
        status: @status
      )
      @operating_units = Organization::Models::OperatingUnit.order(:code)
    end

    def show
      @activity = Cash::Queries::LocationActivity.call(cash_location_id: @cash_location.id)
    end

    def new
      @cash_location = Cash::Models::CashLocation.new(
        status: Cash::Models::CashLocation::STATUS_ACTIVE,
        currency: "USD",
        balancing_required: true
      )
    end

    def create
      operating_unit = Organization::Models::OperatingUnit.find(cash_location_params.fetch(:operating_unit_id))
      attrs = cash_location_params
      @cash_location = Cash::Commands::CreateLocation.call(
        location_type: attrs[:location_type],
        operating_unit: operating_unit,
        responsible_operator_id: attrs[:responsible_operator_id],
        drawer_code: attrs[:drawer_code],
        name: attrs[:name],
        parent_cash_location_id: attrs[:parent_cash_location_id],
        currency: attrs[:currency].presence || "USD",
        balancing_required: attrs[:balancing_required],
        external_reference: attrs[:external_reference]
      )
      redirect_to admin_cash_location_path(@cash_location), notice: "Created cash location #{@cash_location.name}."
    rescue Cash::Commands::CreateLocation::InvalidRequest, ActiveRecord::RecordNotFound, KeyError => e
      @cash_location = Cash::Models::CashLocation.new(cash_location_params)
      @error_message = e.message
      render :new, status: :unprocessable_entity
    end

    def edit; end

    def update
      @cash_location = Cash::Commands::UpdateLocation.call(
        cash_location_id: @cash_location.id,
        attributes: cash_location_params.except(:operating_unit_id, :location_type, :currency)
      )
      redirect_to admin_cash_location_path(@cash_location), notice: "Updated cash location #{@cash_location.name}."
    rescue Cash::Commands::UpdateLocation::InvalidRequest => e
      @error_message = e.message
      render :edit, status: :unprocessable_entity
    end

    def deactivate
      Cash::Commands::DeactivateLocation.call(cash_location_id: @cash_location.id)
      redirect_to admin_cash_location_path(@cash_location), notice: "Deactivated cash location #{@cash_location.name}."
    rescue Cash::Commands::DeactivateLocation::InvalidRequest => e
      redirect_to admin_cash_location_path(@cash_location), alert: e.message
    end

    private

    def load_cash_location
      @cash_location = Cash::Models::CashLocation
        .includes(:operating_unit, :responsible_operator, :parent_cash_location, :cash_balance)
        .find(params[:id])
    end

    def load_form_options
      @operating_units = Organization::Models::OperatingUnit.order(:code)
      @operators = Workspace::Models::Operator.where(active: true).order(:display_name)
      @parent_cash_locations = Cash::Models::CashLocation.order(:operating_unit_id, :location_type, :drawer_code, :name)
      @location_types = Cash::Models::CashLocation::LOCATION_TYPES
      @statuses = Cash::Models::CashLocation::STATUSES
    end

    def cash_location_params
      permitted = params.require(:cash_location).permit(
        :location_type,
        :operating_unit_id,
        :responsible_operator_id,
        :parent_cash_location_id,
        :drawer_code,
        :name,
        :status,
        :currency,
        :balancing_required,
        :external_reference
      ).to_h.symbolize_keys
      permitted[:responsible_operator_id] = nil if permitted[:responsible_operator_id].blank?
      permitted[:parent_cash_location_id] = nil if permitted[:parent_cash_location_id].blank?
      permitted[:drawer_code] = nil if permitted[:drawer_code].blank?
      permitted[:balancing_required] = ActiveModel::Type::Boolean.new.cast(permitted[:balancing_required]) if permitted.key?(:balancing_required)
      permitted
    end
  end
end
