# frozen_string_literal: true

module Teller
  class HoldsController < ApplicationController
    def create
      attrs = params.require(:hold).permit(:deposit_account_id, :amount_minor_units, :currency, :channel, :idempotency_key,
                                           :business_date, :placed_for_operational_event_id).to_h.symbolize_keys
      attrs[:deposit_account_id] = attrs[:deposit_account_id].to_i
      attrs[:amount_minor_units] = attrs[:amount_minor_units].to_i
      if attrs[:placed_for_operational_event_id].present?
        attrs[:placed_for_operational_event_id] = attrs[:placed_for_operational_event_id].to_i
      else
        attrs.delete(:placed_for_operational_event_id)
      end
      if attrs[:business_date].present?
        attrs[:business_date] = Date.iso8601(attrs[:business_date].to_s)
      else
        attrs.delete(:business_date)
      end

      result = Accounts::Commands::PlaceHold.call(**attrs)
      status = result[:outcome] == :created ? :created : :ok
      render json: { hold_id: result[:hold].id, operational_event_id: result[:event].id, outcome: result[:outcome] }, status: status
    rescue Accounts::Commands::PlaceHold::InvalidRequest => e
      render json: { error: "invalid_request", message: e.message }, status: :unprocessable_entity
    end

    def release
      attrs = params.require(:hold_release).permit(:hold_id, :channel, :idempotency_key, :business_date).to_h.symbolize_keys
      attrs[:hold_id] = attrs[:hold_id].to_i
      if attrs[:business_date].present?
        attrs[:business_date] = Date.iso8601(attrs[:business_date].to_s)
      else
        attrs.delete(:business_date)
      end

      result = Accounts::Commands::ReleaseHold.call(**attrs)
      status = result[:outcome] == :created ? :created : :ok
      render json: { operational_event_id: result[:event].id, outcome: result[:outcome] }, status: status
    rescue Accounts::Commands::ReleaseHold::InvalidRequest => e
      render json: { error: "invalid_request", message: e.message }, status: :unprocessable_entity
    rescue Accounts::Commands::ReleaseHold::HoldNotFound => e
      render json: { error: "not_found", message: e.message }, status: :not_found
    end
  end
end
