# frozen_string_literal: true

module Admin
  class ApplicationController < Internal::ApplicationController
    before_action :require_admin_operator!

    private

    def require_admin_capability!(capability_code)
      return if current_operating_unit.present? &&
        current_operator&.has_capability?(capability_code, scope: current_operating_unit)

      render plain: "Forbidden", status: :forbidden
    end

    def parse_optional_date_param(name)
      raw = params[name].presence
      return nil if raw.blank?

      Date.iso8601(raw.to_s)
    rescue ArgumentError, TypeError
      @error_message = "#{name} must be a valid ISO 8601 date (YYYY-MM-DD)"
      nil
    end
  end
end
