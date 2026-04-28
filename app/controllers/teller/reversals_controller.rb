# frozen_string_literal: true

module Teller
  class ReversalsController < ApplicationController
    before_action :require_reversal_capability!, only: [ :create ]

    def create
      attrs = params.require(:reversal).permit(:original_operational_event_id, :channel, :idempotency_key, :business_date).to_h.symbolize_keys
      attrs[:original_operational_event_id] = attrs[:original_operational_event_id].to_i
      if attrs[:business_date].present?
        attrs[:business_date] = Date.iso8601(attrs[:business_date].to_s)
      else
        attrs.delete(:business_date)
      end

      result = Core::OperationalEvents::Commands::RecordReversal.call(**attrs, actor_id: current_operator.id)
      status = result[:outcome] == :created ? :created : :ok
      render json: { id: result[:event].id, outcome: result[:outcome] }, status: status
    rescue Core::OperationalEvents::Commands::RecordReversal::InvalidRequest => e
      render json: { error: "invalid_request", message: e.message }, status: :unprocessable_entity
    rescue Core::OperationalEvents::Commands::RecordReversal::NotFound => e
      render json: { error: "not_found", message: e.message }, status: :not_found
    rescue Core::OperationalEvents::Commands::RecordReversal::MismatchedIdempotency => e
      render json: { error: "idempotency_conflict", fingerprint: e.fingerprint }, status: :conflict
    rescue Core::OperationalEvents::Commands::RecordReversal::PostedReplay => e
      render json: { error: "posted_replay", message: e.message.presence || "already posted" }, status: :conflict
    rescue Workspace::Authorization::Forbidden
      render json: { error: "forbidden", message: "supervisor role required" }, status: :forbidden
    end

    private

    def require_reversal_capability!
      require_capability!(Workspace::Authorization::CapabilityRegistry::REVERSAL_CREATE)
    end
  end
end
