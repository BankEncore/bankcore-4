# frozen_string_literal: true

module Teller
  module AuthenticateOperator
    extend ActiveSupport::Concern

    included do
      before_action :require_operator!
    end

    private

    def require_operator!
      return if performed?

      raw = request.headers["X-Operator-Id"].to_s.strip
      unless raw.match?(/\A\d+\z/)
        render json: { error: "unauthorized", message: "X-Operator-Id header is required" }, status: :unauthorized
        return
      end

      @current_operator = Workspace::Models::Operator.find_by(id: raw.to_i, active: true)
      return if @current_operator

      render json: { error: "unauthorized", message: "unknown or inactive operator" }, status: :unauthorized
    end

    def require_supervisor!
      return if performed?
      return if current_operator&.supervisor?

      render json: { error: "forbidden", message: "supervisor role required" }, status: :forbidden
    end

    def require_capability!(capability_code, message: "supervisor role required")
      return if performed?
      return if current_operator&.has_capability?(capability_code, scope: current_operating_unit)

      render json: { error: "forbidden", message: message }, status: :forbidden
    end

    def current_operator
      @current_operator
    end

    def current_operating_unit
      @current_operating_unit ||= Organization::Services::ResolveOperatingUnit.call(operator: current_operator)
    rescue Organization::Services::ResolveOperatingUnit::Error,
      Organization::Services::DefaultOperatingUnit::AmbiguousDefault,
      Organization::Services::DefaultOperatingUnit::NotFound
      nil
    end
  end
end
