# frozen_string_literal: true

module Branch
  class DashboardController < ApplicationController
    def index
      @session_dashboard = Teller::Queries::BranchSessionDashboard.call
      @supervisor_controls = Teller::Queries::SupervisorControlCatalog.call(
        operating_unit_id: current_operating_unit&.id
      )
    end
  end
end
