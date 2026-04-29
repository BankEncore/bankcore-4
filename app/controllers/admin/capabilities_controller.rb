# frozen_string_literal: true

module Admin
  class CapabilitiesController < ApplicationController
    before_action -> { require_admin_capability!(Workspace::Authorization::CapabilityRegistry::SYSTEM_CONFIGURE) }
    before_action :load_capability, only: %i[show edit update deactivate]

    def index
      @capabilities = Workspace::Queries::RbacCatalog.capabilities.group_by(&:category)
    end

    def show; end

    def new
      @capability = Workspace::Models::Capability.new(active: true)
    end

    def create
      @capability = Workspace::Commands::CreateCapability.call(attributes: capability_params)
      redirect_to admin_capability_path(@capability), notice: "Created capability #{@capability.code}."
    rescue Workspace::Commands::CreateCapability::InvalidRequest => e
      @capability = Workspace::Models::Capability.new(capability_params)
      @error_message = e.message
      render :new, status: :unprocessable_entity
    end

    def edit; end

    def update
      @capability = Workspace::Commands::UpdateCapability.call(
        capability_id: @capability.id,
        attributes: capability_params
      )
      redirect_to admin_capability_path(@capability), notice: "Updated capability #{@capability.code}."
    rescue Workspace::Commands::UpdateCapability::InvalidRequest => e
      @error_message = e.message
      render :edit, status: :unprocessable_entity
    end

    def deactivate
      Workspace::Commands::DeactivateCapability.call(capability_id: @capability.id)
      redirect_to admin_capabilities_path, notice: "Deactivated capability #{@capability.code}."
    rescue Workspace::Commands::DeactivateCapability::InvalidRequest => e
      redirect_to admin_capability_path(@capability), alert: e.message
    end

    private

    def load_capability
      @capability = Workspace::Models::Capability.includes(:roles).find(params[:id])
    end

    def capability_params
      params.require(:capability).permit(:code, :name, :category, :description, :active).to_h
    end
  end
end
