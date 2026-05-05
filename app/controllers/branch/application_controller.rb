# frozen_string_literal: true

module Branch
  class ApplicationController < Internal::ApplicationController
    before_action :require_branch_operator!
    helper_method :branch_operator_can?, :branch_surface_for_path, :branch_teller_session_option_label,
      :can_place_servicing_hold?, :can_release_servicing_hold?, :can_waive_fee?, :can_reverse_event?,
      :can_manage_authorized_signers?, :can_maintain_account?, :can_update_party_contact?,
      :branch_workspace_summary

    private

    def default_idempotency_key(prefix)
      "#{prefix}-#{SecureRandom.hex(8)}"
    end

    def branch_channel
      "branch"
    end

    def post_event_if_requested(event, record_and_post)
      return nil unless ActiveModel::Type::Boolean.new.cast(record_and_post)

      Core::Posting::Commands::PostEvent.call(operational_event_id: event.id).tap { event.reload }
    end

    def parse_optional_integer(value)
      value.presence&.to_i
    end

    def normalize_money_amount_minor_units(display_amount, fallback_minor_units: nil)
      value = display_amount.to_s.strip
      return fallback_minor_units.to_i if value.blank? && fallback_minor_units.present?

      unless valid_money_amount?(value)
        raise ArgumentError, "amount must be greater than 0 with at most 2 decimal places"
      end

      amount = BigDecimal(value.delete(","))
      raise ArgumentError, "amount must be greater than 0" unless amount.positive?

      (amount * 100).to_i
    end

    def money_amount_display(amount, fallback_minor_units: nil)
      value = amount.to_s.strip
      return value if value.present?
      return nil if fallback_minor_units.blank?

      format("%.2f", fallback_minor_units.to_i / 100.0)
    end

    def open_teller_sessions_for_branch
      scope = Teller::Models::TellerSession
        .includes(:cash_location)
        .where(status: Teller::Models::TellerSession::STATUS_OPEN)
      scope = scope.where(operating_unit_id: current_operating_unit.id) if current_operating_unit.present?
      scope.order(:opened_at, :id).to_a
    end

    def branch_teller_session_option_label(session)
      opened_at = session.opened_at&.in_time_zone&.strftime("%Y-%m-%d %H:%M")
      drawer = session.drawer_code.presence || "Drawer #{session.cash_location_id || "unassigned"}"
      "##{session.id} - #{drawer} - opened #{opened_at || "unknown"}"
    end

    def resolve_deposit_account_id(account_id, account_number)
      return account_id if account_id.present?
      return nil if account_number.blank?

      account = Accounts::Models::DepositAccount.find_by(account_number: account_number.to_s.strip)
      raise ActiveRecord::RecordNotFound, "deposit account number #{account_number} not found" if account.nil?

      account.id
    end

    def lookup_deposit_account_id(account_id, account_number)
      resolve_deposit_account_id(account_id, account_number)
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def valid_money_amount?(value)
      return false if value.blank?

      value.match?(/\A(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?\z/)
    end

    def inline_supervisor_operator!(attrs, capability_code:, scope: current_operating_unit)
      username = attrs[:supervisor_username].presence || attrs["supervisor_username"].presence
      password = attrs[:supervisor_password].presence || attrs["supervisor_password"].presence

      if username.blank? && password.blank? && current_operator&.has_capability?(capability_code, scope: scope)
        return current_operator
      end

      credential = Workspace::Models::OperatorCredential.find_for_login(username)
      unless credential&.authenticate(password)
        raise Workspace::Authorization::Forbidden, "inline supervisor credentials are invalid"
      end

      operator = credential.operator
      Workspace::Authorization::Authorizer.require_capability!(
        actor_id: operator.id,
        capability_code: capability_code,
        scope: scope
      )
      operator
    end

    def require_branch_capability!(capability_code, alert: "Supervisor role required")
      return if current_operator&.has_capability?(capability_code, scope: current_operating_unit)

      redirect_to branch_path, alert: alert
    end

    def branch_operator_can?(capability_code)
      current_operator.present? &&
        current_operator.has_capability?(capability_code, scope: current_operating_unit)
    end

    def load_account_context!(deposit_account_id:)
      @profile = Accounts::Queries::DepositAccountProfile.call(deposit_account_id: deposit_account_id)
      @account = @profile.account
      @customer_return_params = params[:query].present? ? { query: params[:query] } : {}
    end

    def branch_surface_for_path(path = request.path)
      case path
      when %r{\A/branch/events(?:/|\z)}, %r{\A/branch/operational_events(?:/|\z)}
        "events"
      when %r{\A/branch/approvals(?:/|\z)}, %r{\A/branch/reversals(?:/|\z)}, %r{\A/branch/overrides(?:/|\z)}
        "supervisor"
      when %r{\A/branch/teller(?:/|\z)}, %r{\A/branch/teller_sessions(?:/|\z)}, %r{\A/branch/deposits(?:/|\z)},
           %r{\A/branch/check_deposits(?:/|\z)}, %r{\A/branch/withdrawals(?:/|\z)}, %r{\A/branch/transfers(?:/|\z)},
           %r{\A/branch/holds(?:/|\z)}, %r{\A/branch/cash(?:/|\z)}
        "teller"
      when %r{\A/branch/customers(?:/|\z)}, %r{\A/branch/accounts(?:/|\z)}, %r{\A/branch/deposit_accounts(?:/|\z)},
           %r{\A/branch/parties(?:/|\z)}
        "csr"
      else
        "teller"
      end
    end

    def branch_workspace_summary
      @branch_workspace_summary ||= Teller::Queries::BranchSessionDashboard.call
    end

    def can_place_servicing_hold?
      branch_operator_can?(Workspace::Authorization::CapabilityRegistry::HOLD_PLACE)
    end

    def can_release_servicing_hold?
      current_operator&.has_capability?(Workspace::Authorization::CapabilityRegistry::HOLD_RELEASE, scope: current_operating_unit)
    end

    def can_waive_fee?
      current_operator&.has_capability?(Workspace::Authorization::CapabilityRegistry::FEE_WAIVE, scope: current_operating_unit)
    end

    def can_reverse_event?
      current_operator&.has_capability?(Workspace::Authorization::CapabilityRegistry::REVERSAL_CREATE, scope: current_operating_unit)
    end

    def can_manage_authorized_signers?
      current_operator&.has_capability?(Workspace::Authorization::CapabilityRegistry::ACCOUNT_MAINTAIN, scope: current_operating_unit)
    end

    def can_maintain_account?
      current_operator&.has_capability?(Workspace::Authorization::CapabilityRegistry::ACCOUNT_MAINTAIN, scope: current_operating_unit)
    end

    def can_update_party_contact?
      current_operator&.has_capability?(Workspace::Authorization::CapabilityRegistry::PARTY_CONTACT_UPDATE, scope: current_operating_unit)
    end
  end
end
