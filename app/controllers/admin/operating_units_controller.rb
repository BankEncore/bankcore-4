# frozen_string_literal: true

module Admin
  class OperatingUnitsController < ApplicationController
    before_action -> { require_admin_capability!(Workspace::Authorization::CapabilityRegistry::SYSTEM_CONFIGURE) }
    before_action :load_operating_unit, only: %i[show edit update close]
    before_action :load_form_options, only: %i[new create edit update show]

    def index
      @status = params[:status].presence
      @unit_type = params[:unit_type].presence
      @operating_units = Organization::Queries::OperatingUnitDirectory.call(status: @status, unit_type: @unit_type)
      @child_counts = Organization::Models::OperatingUnit.group(:parent_operating_unit_id).count
      @cash_location_counts = Cash::Models::CashLocation.group(:operating_unit_id).count
    end

    def show
      @child_units = @operating_unit.child_operating_units.order(:code)
      @defaulting_operators = Workspace::Models::Operator
        .where(default_operating_unit_id: @operating_unit.id)
        .order(:display_name)
      @scoped_assignments = Workspace::Models::OperatorRoleAssignment
        .includes(:operator, :role)
        .where(scope_type: "operating_unit", scope_id: @operating_unit.id)
        .order(active: :desc, id: :desc)
      @cash_locations = Cash::Models::CashLocation
        .includes(:cash_balance)
        .where(operating_unit_id: @operating_unit.id)
        .order(:location_type, :drawer_code, :name)
    end

    def new
      @operating_unit = Organization::Models::OperatingUnit.new(
        status: Organization::Models::OperatingUnit::STATUS_ACTIVE,
        time_zone: "Eastern Time (US & Canada)"
      )
    end

    def create
      @operating_unit = Organization::Commands::CreateOperatingUnit.call(attributes: operating_unit_params)
      redirect_to admin_operating_unit_path(@operating_unit), notice: "Created operating unit #{@operating_unit.code}."
    rescue Organization::Commands::CreateOperatingUnit::InvalidRequest => e
      @operating_unit = Organization::Models::OperatingUnit.new(operating_unit_params)
      @error_message = e.message
      render :new, status: :unprocessable_entity
    end

    def edit; end

    def update
      @operating_unit = Organization::Commands::UpdateOperatingUnit.call(
        operating_unit_id: @operating_unit.id,
        attributes: operating_unit_params
      )
      redirect_to admin_operating_unit_path(@operating_unit), notice: "Updated operating unit #{@operating_unit.code}."
    rescue Organization::Commands::UpdateOperatingUnit::InvalidRequest => e
      @error_message = e.message
      render :edit, status: :unprocessable_entity
    end

    def close
      Organization::Commands::CloseOperatingUnit.call(
        operating_unit_id: @operating_unit.id,
        closed_on: params.dig(:operating_unit, :closed_on)
      )
      redirect_to admin_operating_unit_path(@operating_unit), notice: "Closed operating unit #{@operating_unit.code}."
    rescue Organization::Commands::CloseOperatingUnit::InvalidRequest => e
      redirect_to admin_operating_unit_path(@operating_unit), alert: e.message
    end

    private

    def load_operating_unit
      @operating_unit = Organization::Models::OperatingUnit.includes(:parent_operating_unit).find(params[:id])
    end

    def load_form_options
      @parent_operating_units = Organization::Models::OperatingUnit.order(:code)
      @unit_types = Organization::Models::OperatingUnit::UNIT_TYPES
      @statuses = Organization::Models::OperatingUnit::STATUSES
    end

    def operating_unit_params
      params.require(:operating_unit).permit(
        :code, :name, :unit_type, :status, :parent_operating_unit_id, :time_zone, :opened_on, :closed_on
      ).to_h
    end
  end
end
