# frozen_string_literal: true

module Admin
  class RolesController < ApplicationController
    before_action -> { require_admin_capability!(Workspace::Authorization::CapabilityRegistry::ROLE_MANAGE) }
    before_action :load_role, only: %i[show edit update deactivate update_capabilities]
    before_action :load_capabilities, only: %i[show new create edit update]

    def index
      @roles = Workspace::Queries::RbacCatalog.roles
    end

    def show
      @assignments = @role.operator_role_assignments.includes(:operator).order(active: :desc, id: :desc)
    end

    def new
      @role = Workspace::Models::Role.new(active: true)
    end

    def create
      @role = Workspace::Commands::CreateRole.call(attributes: role_params)
      Workspace::Commands::UpdateRoleCapabilities.call(role_id: @role.id, capability_ids: params[:capability_ids])
      redirect_to admin_role_path(@role), notice: "Created role #{@role.code}."
    rescue Workspace::Commands::CreateRole::InvalidRequest, Workspace::Commands::UpdateRoleCapabilities::InvalidRequest => e
      @role = Workspace::Models::Role.new(role_params)
      @error_message = e.message
      render :new, status: :unprocessable_entity
    end

    def edit; end

    def update
      @role = Workspace::Commands::UpdateRole.call(role_id: @role.id, attributes: role_params)
      redirect_to admin_role_path(@role), notice: "Updated role #{@role.code}."
    rescue Workspace::Commands::UpdateRole::InvalidRequest => e
      @error_message = e.message
      render :edit, status: :unprocessable_entity
    end

    def update_capabilities
      Workspace::Commands::UpdateRoleCapabilities.call(role_id: @role.id, capability_ids: params[:capability_ids])
      redirect_to admin_role_path(@role), notice: "Updated role capabilities for #{@role.code}."
    rescue Workspace::Commands::UpdateRoleCapabilities::InvalidRequest => e
      redirect_to admin_role_path(@role), alert: e.message
    end

    def deactivate
      Workspace::Commands::DeactivateRole.call(role_id: @role.id)
      redirect_to admin_roles_path, notice: "Deactivated role #{@role.code}."
    rescue Workspace::Commands::DeactivateRole::InvalidRequest => e
      redirect_to admin_role_path(@role), alert: e.message
    end

    private

    def load_role
      @role = Workspace::Models::Role.includes(:capabilities).find(params[:id])
    end

    def load_capabilities
      @capabilities = Workspace::Queries::RbacCatalog.capabilities.group_by(&:category)
    end

    def role_params
      params.require(:role).permit(:code, :name, :description, :active).to_h
    end
  end
end
