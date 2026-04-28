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
      has_any_capability?(
        Workspace::Authorization::CapabilityRegistry::DEPOSIT_ACCEPT,
        Workspace::Authorization::CapabilityRegistry::ACCOUNT_OPEN,
        Workspace::Authorization::CapabilityRegistry::ACCOUNT_MAINTAIN,
        Workspace::Authorization::CapabilityRegistry::HOLD_PLACE
      )
    end

    def ops_access?
      has_any_capability?(
        Workspace::Authorization::CapabilityRegistry::OPS_BATCH_PROCESS,
        Workspace::Authorization::CapabilityRegistry::OPS_EXCEPTION_RESOLVE,
        Workspace::Authorization::CapabilityRegistry::OPS_RECONCILIATION_PERFORM,
        Workspace::Authorization::CapabilityRegistry::SYSTEM_CONFIGURE
      )
    end

    def admin_access?
      has_any_capability?(
        Workspace::Authorization::CapabilityRegistry::USER_MANAGE,
        Workspace::Authorization::CapabilityRegistry::ROLE_MANAGE,
        Workspace::Authorization::CapabilityRegistry::SYSTEM_CONFIGURE
      )
    end

    def has_any_capability?(*capability_codes)
      capability_codes.any? { |code| current_operator&.has_capability?(code) }
    end
  end
end
