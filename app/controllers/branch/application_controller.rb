# frozen_string_literal: true

module Branch
  class ApplicationController < Internal::ApplicationController
    before_action :require_branch_operator!
    helper_method :can_place_servicing_hold?, :can_release_servicing_hold?, :can_waive_fee?, :can_reverse_event?,
      :can_manage_authorized_signers?

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

    def require_branch_supervisor!
      return if current_operator&.supervisor?

      redirect_to branch_path, alert: "Supervisor role required"
    end

    def require_branch_capability!(capability_code, alert: "Supervisor role required")
      return if current_operator&.has_capability?(capability_code)

      redirect_to branch_path, alert: alert
    end

    def can_place_servicing_hold?
      current_operator&.teller? || current_operator&.supervisor?
    end

    def can_release_servicing_hold?
      current_operator&.has_capability?(Workspace::Authorization::CapabilityRegistry::HOLD_RELEASE)
    end

    def can_waive_fee?
      current_operator&.has_capability?(Workspace::Authorization::CapabilityRegistry::FEE_WAIVE)
    end

    def can_reverse_event?
      current_operator&.has_capability?(Workspace::Authorization::CapabilityRegistry::REVERSAL_CREATE)
    end

    def can_manage_authorized_signers?
      current_operator&.has_capability?(Workspace::Authorization::CapabilityRegistry::ACCOUNT_MAINTAIN)
    end
  end
end
