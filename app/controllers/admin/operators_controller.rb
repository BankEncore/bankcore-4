# frozen_string_literal: true

module Admin
  class OperatorsController < ApplicationController
    before_action -> { require_admin_capability!(Workspace::Authorization::CapabilityRegistry::USER_MANAGE) }
    before_action :load_operator, only: %i[show edit update deactivate reset_credential]
    before_action :load_form_options, only: %i[new create edit update show]

    def index
      @status = params[:status].presence
      @search = params[:search].presence
      @operators = Workspace::Queries::OperatorDirectory.call(search: @search, status: @status)
    end

    def show
      @assignments = @operator.operator_role_assignments.includes(:role).order(:active, :id)
      @effective_capabilities = current_scope_capabilities(@operator)
    end

    def new
      @operator = Workspace::Models::Operator.new(active: true)
    end

    def create
      @operator = Workspace::Commands::CreateOperator.call(attributes: operator_params)
      redirect_to admin_operator_path(@operator), notice: "Created operator #{@operator.display_name}."
    rescue Workspace::Commands::CreateOperator::InvalidRequest => e
      @operator = Workspace::Models::Operator.new(operator_params.except(:username, :password))
      @error_message = e.message
      render :new, status: :unprocessable_entity
    end

    def edit; end

    def update
      @operator = Workspace::Commands::UpdateOperator.call(operator_id: @operator.id, attributes: operator_params)
      redirect_to admin_operator_path(@operator), notice: "Updated operator #{@operator.display_name}."
    rescue Workspace::Commands::UpdateOperator::InvalidRequest => e
      @error_message = e.message
      render :edit, status: :unprocessable_entity
    end

    def deactivate
      Workspace::Commands::DeactivateOperator.call(operator_id: @operator.id)
      redirect_to admin_operator_path(@operator), notice: "Deactivated operator #{@operator.display_name}."
    rescue Workspace::Commands::DeactivateOperator::InvalidRequest => e
      redirect_to admin_operator_path(@operator), alert: e.message
    end

    def reset_credential
      Workspace::Commands::ResetOperatorCredential.call(
        operator_id: @operator.id,
        username: params.dig(:credential, :username),
        password: params.dig(:credential, :password)
      )
      redirect_to admin_operator_path(@operator), notice: "Reset credentials for #{@operator.display_name}."
    rescue Workspace::Commands::ResetOperatorCredential::InvalidRequest => e
      redirect_to admin_operator_path(@operator), alert: e.message
    end

    private

    def load_operator
      @operator = Workspace::Models::Operator.includes(:credential, :default_operating_unit).find(params[:id])
    end

    def load_form_options
      @operating_units = Workspace::Queries::RbacCatalog.operating_units
      @legacy_roles = Workspace::Models::Operator::ROLES
    end

    def operator_params
      permitted = params.require(:operator).permit(
        :display_name, :role, :active, :default_operating_unit_id, :username, :password
      ).to_h
      permitted[:active] = ActiveModel::Type::Boolean.new.cast(permitted[:active]) if permitted.key?(:active)
      permitted[:default_operating_unit_id] = nil if permitted[:default_operating_unit_id].blank?
      permitted
    end

    def current_scope_capabilities(operator)
      return [] if operator.default_operating_unit.blank?

      operator.capabilities(scope: operator.default_operating_unit)
    end
  end
end
