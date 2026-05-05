# frozen_string_literal: true

module Branch
  class DashboardController < ApplicationController
    def index
      load_dashboard(surface: "teller")
    end

    def teller
      load_dashboard(surface: "teller")
      render :index
    end

    def approvals
      load_dashboard(surface: "supervisor")
      render :index
    end

    private

    def load_dashboard(surface:)
      @branch_surface = surface
      @branch_section_order = section_order(surface)
      @session_dashboard = Teller::Queries::BranchSessionDashboard.call
      @supervisor_controls = Teller::Queries::SupervisorControlCatalog.call(
        operating_unit_id: current_operating_unit&.id
      )
    end

    def section_order(surface)
      surfaces = [ "csr", "teller", "supervisor" ]
      surfaces.delete(surface)
      [ surface, *surfaces ]
    end
  end
end
