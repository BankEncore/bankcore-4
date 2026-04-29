# frozen_string_literal: true

module Teller
  class CashController < ApplicationController
    before_action -> { require_capability!(Workspace::Authorization::CapabilityRegistry::CASH_POSITION_VIEW) },
      only: [ :locations, :position, :activity, :approvals, :reconciliation ]
    before_action -> { require_capability!(Workspace::Authorization::CapabilityRegistry::CASH_LOCATION_MANAGE) },
      only: [ :create_location ]
    before_action -> { require_capability!(Workspace::Authorization::CapabilityRegistry::CASH_MOVEMENT_CREATE) },
      only: [ :create_transfer ]
    before_action -> { require_capability!(Workspace::Authorization::CapabilityRegistry::CASH_MOVEMENT_APPROVE) },
      only: [ :approve_transfer ]
    before_action -> { require_capability!(Workspace::Authorization::CapabilityRegistry::CASH_COUNT_RECORD) },
      only: [ :create_count ]
    before_action -> { require_capability!(Workspace::Authorization::CapabilityRegistry::CASH_VARIANCE_APPROVE) },
      only: [ :approve_variance ]

    def locations
      render json: { locations: Cash::Queries::CashPosition.call(operating_unit_id: params[:operating_unit_id]) }
    end

    def create_location
      attrs = params.require(:cash_location).permit(
        :location_type, :operating_unit_id, :responsible_operator_id, :drawer_code, :name, :parent_cash_location_id
      )
      location = Cash::Commands::CreateLocation.call(**attrs.to_h.symbolize_keys, actor_id: current_operator.id)
      render json: serialize_location(location), status: :created
    rescue Cash::Commands::CreateLocation::Error => e
      render json: { error: "invalid_request", message: e.message }, status: :unprocessable_entity
    end

    def create_transfer
      attrs = params.require(:cash_transfer).permit(
        :source_cash_location_id, :destination_cash_location_id, :amount_minor_units, :idempotency_key, :reason_code
      ).to_h.symbolize_keys
      movement = Cash::Commands::TransferCash.call(**attrs, actor_id: current_operator.id, channel: "teller")
      render json: serialize_movement(movement), status: :created
    rescue Cash::Commands::TransferCash::Error => e
      render json: { error: "invalid_request", message: e.message }, status: :unprocessable_entity
    end

    def approve_transfer
      movement = Cash::Commands::ApproveCashMovement.call(
        cash_movement_id: params.require(:cash_movement_id).to_i,
        approving_actor_id: current_operator.id,
        channel: "teller"
      )
      render json: serialize_movement(movement)
    rescue Cash::Commands::ApproveCashMovement::Error => e
      render json: { error: "invalid_state", message: e.message }, status: :unprocessable_entity
    end

    def create_count
      attrs = params.require(:cash_count).permit(
        :cash_location_id, :counted_amount_minor_units, :expected_amount_minor_units, :idempotency_key
      ).to_h.symbolize_keys
      count = Cash::Commands::RecordCashCount.call(**attrs, actor_id: current_operator.id, channel: "teller")
      render json: serialize_count(count), status: :created
    rescue Cash::Commands::RecordCashCount::Error => e
      render json: { error: "invalid_request", message: e.message }, status: :unprocessable_entity
    end

    def approve_variance
      variance = Cash::Commands::ApproveCashVariance.call(
        cash_variance_id: params.require(:cash_variance_id).to_i,
        approving_actor_id: current_operator.id
      )
      render json: serialize_variance(variance)
    rescue Cash::Commands::ApproveCashVariance::Error => e
      render json: { error: "invalid_state", message: e.message }, status: :unprocessable_entity
    end

    def position
      render json: { locations: Cash::Queries::CashPosition.call(operating_unit_id: params[:operating_unit_id]) }
    end

    def activity
      activity = Cash::Queries::LocationActivity.call(cash_location_id: params.require(:cash_location_id).to_i)
      render json: {
        location: serialize_location(activity.fetch(:location)),
        movements: activity.fetch(:movements).map { |movement| serialize_movement(movement) },
        counts: activity.fetch(:counts).map { |count| serialize_count(count) },
        variances: activity.fetch(:variances).map { |variance| serialize_variance(variance) }
      }
    end

    def approvals
      render json: Cash::Queries::PendingCashApprovals.call(operating_unit_id: params[:operating_unit_id])
    end

    def reconciliation
      render json: Cash::Queries::ReconciliationSummary.call(
        operating_unit_id: params[:operating_unit_id],
        business_date: params[:business_date].presence
      )
    end

    private

    def serialize_location(location)
      {
        id: location.id,
        location_type: location.location_type,
        name: location.name,
        drawer_code: location.drawer_code,
        operating_unit_id: location.operating_unit_id,
        status: location.status
      }
    end

    def serialize_movement(movement)
      movement.as_json(only: [
        :id, :source_cash_location_id, :destination_cash_location_id, :amount_minor_units, :currency,
        :business_date, :status, :movement_type, :operational_event_id, :actor_id, :approving_actor_id
      ])
    end

    def serialize_count(count)
      count.as_json(only: [
        :id, :cash_location_id, :counted_amount_minor_units, :expected_amount_minor_units, :currency,
        :business_date, :status, :operational_event_id, :actor_id
      ]).merge(cash_variance_id: count.cash_variance&.id)
    end

    def serialize_variance(variance)
      variance.as_json(only: [
        :id, :cash_location_id, :cash_count_id, :amount_minor_units, :currency, :business_date,
        :status, :actor_id, :approving_actor_id, :cash_variance_posted_event_id
      ])
    end
  end
end
