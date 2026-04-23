# frozen_string_literal: true

module Teller
  class OperationalEventsController < ApplicationController
    def create
      attrs = params.require(:operational_event).permit(
        :event_type, :channel, :idempotency_key, :amount_minor_units, :currency, :source_account_id,
        :destination_account_id, :teller_session_id, :business_date
      ).to_h.symbolize_keys
      attrs[:amount_minor_units] = attrs[:amount_minor_units].to_i
      attrs[:source_account_id] = attrs[:source_account_id].to_i
      if attrs[:destination_account_id].present?
        attrs[:destination_account_id] = attrs[:destination_account_id].to_i
      else
        attrs.delete(:destination_account_id)
      end
      if attrs[:teller_session_id].present?
        attrs[:teller_session_id] = attrs[:teller_session_id].to_i
      else
        attrs.delete(:teller_session_id)
      end
      if attrs[:business_date].present?
        attrs[:business_date] = Date.iso8601(attrs[:business_date].to_s)
      else
        attrs.delete(:business_date)
      end

      result = Core::OperationalEvents::Commands::RecordEvent.call(**attrs, actor_id: current_operator.id)
      status = result[:outcome] == :created ? :created : :ok
      render json: {
        id: result[:event].id,
        outcome: result[:outcome],
        operational_event_id: result[:event].id
      }, status: status
    rescue Core::OperationalEvents::Commands::RecordEvent::InvalidRequest => e
      render json: { error: "invalid_request", message: e.message }, status: :unprocessable_entity
    rescue Core::OperationalEvents::Commands::RecordEvent::MismatchedIdempotency => e
      render json: { error: "idempotency_conflict", fingerprint: e.fingerprint }, status: :conflict
    rescue Core::OperationalEvents::Commands::RecordEvent::PostedReplay => e
      render json: { error: "posted_replay", message: e.message.presence || "already posted" }, status: :conflict
    end
  end
end
