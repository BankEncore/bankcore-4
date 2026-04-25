# frozen_string_literal: true

module Internal
  class ApplicationController < ::ApplicationController
    layout "internal"

    before_action :require_internal_operator!

    helper_method :current_operator, :current_business_date, :branch_access?, :ops_access?, :admin_access?

    private

    def require_internal_operator!
      return if current_operator

      redirect_to login_path, alert: "Please sign in"
    end

    def current_operator
      @current_operator ||= Workspace::Models::Operator.find_by(id: session[:operator_id], active: true)
    end

    def current_business_date
      @current_business_date ||= Core::BusinessDate::Services::CurrentBusinessDate.call
    rescue Core::BusinessDate::Errors::NotSet
      nil
    end

    def require_branch_operator!
      return if branch_access?

      render plain: "Forbidden", status: :forbidden
    end

    def require_ops_operator!
      return if ops_access?

      render plain: "Forbidden", status: :forbidden
    end

    def require_admin_operator!
      return if admin_access?

      render plain: "Forbidden", status: :forbidden
    end

    def branch_access?
      current_operator&.teller? || current_operator&.supervisor?
    end

    def ops_access?
      current_operator&.operations? || current_operator&.admin?
    end

    def admin_access?
      current_operator&.admin?
    end
  end
end
