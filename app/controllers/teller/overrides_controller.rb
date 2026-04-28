# frozen_string_literal: true

module Teller
  class OverridesController < ApplicationController
    before_action :require_supervisor_for_override_approval!, only: [ :create ]

    def create
      attrs = params.require(:override).permit(:event_type, :channel, :idempotency_key, :reference_id, :business_date).to_h.symbolize_keys
      attrs[:actor_id] = current_operator.id
      attrs[:operating_unit_id] = current_operating_unit&.id
      if attrs[:business_date].present?
        attrs[:business_date] = Date.iso8601(attrs[:business_date].to_s)
      else
        attrs.delete(:business_date)
      end

      result = Core::OperationalEvents::Commands::RecordControlEvent.call(**attrs)
      status = result[:outcome] == :created ? :created : :ok
      render json: { id: result[:event].id, outcome: result[:outcome] }, status: status
    rescue Core::OperationalEvents::Commands::RecordControlEvent::InvalidRequest => e
      render json: { error: "invalid_request", message: e.message }, status: :unprocessable_entity
    rescue Core::OperationalEvents::Commands::RecordControlEvent::MismatchedIdempotency => e
      render json: { error: "idempotency_conflict", fingerprint: e.fingerprint }, status: :conflict
    end

    private

    def require_supervisor_for_override_approval!
      return if performed?
      return unless params.dig(:override, :event_type).to_s == "override.approved"

      require_supervisor!
    end
  end
end
