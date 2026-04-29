# frozen_string_literal: true

module Admin
  class OperatorRoleAssignmentsController < ApplicationController
    before_action -> { require_admin_capability!(Workspace::Authorization::CapabilityRegistry::ROLE_MANAGE) }
    before_action :load_operator
    before_action :load_assignment, only: %i[edit update deactivate]
    before_action :load_form_options, only: %i[new edit create update]

    def new
      @assignment = @operator.operator_role_assignments.build(active: true, scope_type: "operating_unit")
    end

    def create
      @assignment = Workspace::Commands::AssignOperatorRole.call(attributes: assignment_params.merge(operator_id: @operator.id))
      redirect_to admin_operator_path(@operator), notice: "Assigned role #{@assignment.role.code}."
    rescue Workspace::Commands::AssignOperatorRole::InvalidRequest => e
      @assignment = @operator.operator_role_assignments.build(assignment_params)
      @error_message = e.message
      render :new, status: :unprocessable_entity
    end

    def edit; end

    def update
      @assignment = Workspace::Commands::UpdateOperatorRoleAssignment.call(
        assignment_id: @assignment.id,
        attributes: assignment_params
      )
      redirect_to admin_operator_path(@operator), notice: "Updated role assignment."
    rescue Workspace::Commands::UpdateOperatorRoleAssignment::InvalidRequest => e
      @error_message = e.message
      render :edit, status: :unprocessable_entity
    end

    def deactivate
      Workspace::Commands::DeactivateOperatorRoleAssignment.call(assignment_id: @assignment.id)
      redirect_to admin_operator_path(@operator), notice: "Deactivated role assignment."
    rescue Workspace::Commands::DeactivateOperatorRoleAssignment::InvalidRequest => e
      redirect_to admin_operator_path(@operator), alert: e.message
    end

    private

    def load_operator
      @operator = Workspace::Models::Operator.find(params[:operator_id])
    end

    def load_assignment
      @assignment = @operator.operator_role_assignments.find(params[:id])
    end

    def load_form_options
      @roles = Workspace::Queries::RbacCatalog.active_roles
      @operating_units = Workspace::Queries::RbacCatalog.operating_units
    end

    def assignment_params
      params.require(:operator_role_assignment).permit(
        :role_id, :scope_type, :scope_id, :active, :starts_at, :ends_at
      ).to_h
    end
  end
end
