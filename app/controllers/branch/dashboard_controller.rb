# frozen_string_literal: true

module Branch
  class DashboardController < ApplicationController
    def index
      @session_dashboard = Teller::Queries::BranchSessionDashboard.call
    end
  end
end
