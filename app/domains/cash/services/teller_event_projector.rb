# frozen_string_literal: true

module Cash
  module Services
    class TellerEventProjector
      CASH_EVENT_DELTAS = {
        "deposit.accepted" => 1,
        "withdrawal.posted" => -1
      }.freeze

      def self.call(operational_event_id:)
        new(operational_event_id: operational_event_id).call
      end

      def initialize(operational_event_id:)
        @operational_event_id = operational_event_id
      end

      def call
        Cash::Models::CashTellerEventProjection.transaction do
          existing = Cash::Models::CashTellerEventProjection.lock.find_by(operational_event_id: operational_event_id)
          return existing if existing.present?

          event = Core::OperationalEvents::Models::OperationalEvent.lock.find_by(id: operational_event_id)
          return nil unless event&.status == Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED

          attrs = projection_attrs_for(event)
          return nil if attrs.nil?

          projection = Cash::Models::CashTellerEventProjection.create!(attrs)
          Cash::Services::BalanceProjector.apply_teller_event_projection!(projection)
          projection
        end
      end

      private

      attr_reader :operational_event_id

      def projection_attrs_for(event)
        if event.event_type == "posting.reversal"
          reversal_projection_attrs(event)
        else
          teller_cash_projection_attrs(event)
        end
      end

      def teller_cash_projection_attrs(event)
        return nil unless CASH_EVENT_DELTAS.key?(event.event_type)
        return nil if event.teller_session_id.blank?

        session = Teller::Models::TellerSession.includes(:cash_location).find_by(id: event.teller_session_id)
        return nil unless session&.cash_location&.teller_drawer?

        delta = event.amount_minor_units.to_i * CASH_EVENT_DELTAS.fetch(event.event_type)
        base_projection_attrs(
          event: event,
          session: session,
          projection_type: Cash::Models::CashTellerEventProjection::PROJECTION_TYPE_TELLER_CASH_EVENT,
          delta_minor_units: delta
        )
      end

      def reversal_projection_attrs(event)
        original = event.reversal_of_event
        return nil if original.nil?

        original_attrs = teller_cash_projection_attrs(original)
        return nil if original_attrs.nil?

        original_attrs.merge(
          operational_event: event,
          reversal_of_operational_event: original,
          projection_type: Cash::Models::CashTellerEventProjection::PROJECTION_TYPE_TELLER_CASH_REVERSAL,
          event_type: event.event_type,
          amount_minor_units: event.amount_minor_units.to_i,
          delta_minor_units: -original_attrs.fetch(:delta_minor_units),
          currency: event.currency,
          business_date: event.business_date,
          applied_at: Time.current
        )
      end

      def base_projection_attrs(event:, session:, projection_type:, delta_minor_units:)
        {
          operational_event: event,
          reversal_of_operational_event: nil,
          teller_session: session,
          cash_location: session.cash_location,
          projection_type: projection_type,
          event_type: event.event_type,
          amount_minor_units: event.amount_minor_units.to_i,
          delta_minor_units: delta_minor_units,
          currency: event.currency,
          business_date: event.business_date,
          applied_at: Time.current
        }
      end
    end
  end
end
