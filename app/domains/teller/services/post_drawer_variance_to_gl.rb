# frozen_string_literal: true

module Teller
  module Services
    # When ADR-0020 flag is on, records and posts teller.drawer.variance.posted for non-zero closed-session variance.
    module PostDrawerVarianceToGl
      module_function

      def call(session:, actor_id: nil)
        return unless Rails.application.config.x.teller.post_drawer_variance_to_gl
        return if session.variance_minor_units.nil? || session.variance_minor_units.to_i.zero?
        return unless session.status == Teller::Models::TellerSession::STATUS_CLOSED

        idem = "drawer-variance-#{session.id}"
        r = Core::OperationalEvents::Commands::RecordEvent.call(
          event_type: "teller.drawer.variance.posted",
          channel: "system",
          idempotency_key: idem,
          amount_minor_units: session.variance_minor_units.to_i,
          currency: "USD",
          source_account_id: nil,
          teller_session_id: session.id,
          actor_id: actor_id,
          operating_unit_id: session.operating_unit_id
        )
        ev = r[:event]
        return if ev.status == Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED

        Core::Posting::Commands::PostEvent.call(operational_event_id: ev.id)
      end
    end
  end
end
