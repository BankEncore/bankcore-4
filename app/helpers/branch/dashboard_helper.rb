# frozen_string_literal: true

module Branch
  module DashboardHelper
    def branch_session_time(value)
      return "Not recorded" if value.blank?

      value.in_time_zone.strftime("%Y-%m-%d %H:%M")
    end
  end
end
