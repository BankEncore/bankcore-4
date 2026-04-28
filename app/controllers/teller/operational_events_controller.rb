# frozen_string_literal: true

module Teller
  class OperationalEventsController < ApplicationController
    def index
      qp = index_query_params
      result = Core::OperationalEvents::Queries::ListOperationalEvents.call(
        business_date: qp[:business_date],
        business_date_from: qp[:business_date_from],
        business_date_to: qp[:business_date_to],
        source_account_id: qp[:source_account_id],
        destination_account_id: qp[:destination_account_id],
        status: qp[:status],
        event_type: qp[:event_type],
        channel: qp[:channel],
        actor_id: qp[:actor_id],
        deposit_product_id: qp[:deposit_product_id],
        product_code: qp[:product_code],
        after_id: qp[:after_id],
        limit: qp[:limit]
      )
      env = result[:envelope]
      render json: {
        current_business_on: env[:current_business_on].iso8601,
        posting_day_closed: env[:posting_day_closed],
        business_date_from: env[:business_date_from].iso8601,
        business_date_to: env[:business_date_to].iso8601,
        next_after_id: result[:next_after_id],
        has_more: result[:has_more],
        events: result[:rows].map { |e| operational_event_list_json(e) }
      }
    rescue Core::OperationalEvents::Queries::ListOperationalEvents::InvalidQuery => e
      render json: { error: "invalid_request", message: e.message }, status: :unprocessable_entity
    rescue Core::BusinessDate::Errors::NotSet => e
      render json: { error: "business_date_not_set", message: e.message }, status: :unprocessable_entity
    end

    def create
      attrs = params.require(:operational_event).permit(
        :event_type, :channel, :idempotency_key, :amount_minor_units, :currency, :source_account_id,
        :destination_account_id, :teller_session_id, :business_date, :reference_id
      ).to_h.symbolize_keys
      attrs[:amount_minor_units] = attrs[:amount_minor_units].to_i
      if attrs[:source_account_id].present?
        attrs[:source_account_id] = attrs[:source_account_id].to_i
      else
        attrs.delete(:source_account_id)
      end
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
      attrs[:reference_id] = attrs[:reference_id].presence

      result = record_operational_event(attrs)
      if result[:outcome].in?([ Accounts::Commands::AuthorizeDebit::OUTCOME_DENIED, Accounts::Commands::AuthorizeDebit::OUTCOME_DENIED_REPLAY ])
        render json: {
          error: "nsf_denied",
          outcome: result[:outcome],
          denial_event_id: result[:denial_event].id,
          fee_event_id: result[:fee_event].id
        }, status: :unprocessable_entity
        return
      end

      status = result[:outcome] == :created ? :created : :ok
      render json: {
        id: result[:event].id,
        outcome: result[:outcome],
        operational_event_id: result[:event].id
      }, status: status
    rescue Core::OperationalEvents::Commands::RecordEvent::InvalidRequest => e
      render json: { error: "invalid_request", message: e.message }, status: :unprocessable_entity
    rescue Accounts::Commands::AuthorizeDebit::InvalidRequest => e
      render json: { error: "invalid_request", message: e.message }, status: :unprocessable_entity
    rescue Core::OperationalEvents::Commands::RecordEvent::MismatchedIdempotency => e
      render json: { error: "idempotency_conflict", fingerprint: e.fingerprint }, status: :conflict
    rescue Core::OperationalEvents::Commands::RecordEvent::PostedReplay => e
      render json: { error: "posted_replay", message: e.message.presence || "already posted" }, status: :conflict
    rescue Workspace::Authorization::Forbidden
      render json: { error: "forbidden", message: "supervisor role required" }, status: :forbidden
    end

    private

    def record_operational_event(attrs)
      if %w[withdrawal.posted transfer.completed].include?(attrs[:event_type].to_s)
        Accounts::Commands::AuthorizeDebit.call(**attrs, actor_id: current_operator.id)
      else
        Core::OperationalEvents::Commands::RecordEvent.call(**attrs, actor_id: current_operator.id)
      end
    end

    def index_query_params
      p = params.permit(
        :business_date, :business_date_from, :business_date_to,
        :source_account_id, :destination_account_id, :status, :event_type, :channel, :actor_id,
        :deposit_product_id, :product_code, :after_id, :limit
      ).to_h.symbolize_keys
      p[:source_account_id] = p[:source_account_id].to_i if p[:source_account_id].present?
      p[:destination_account_id] = p[:destination_account_id].to_i if p[:destination_account_id].present?
      p[:actor_id] = p[:actor_id].to_i if p[:actor_id].present?
      p[:deposit_product_id] = p[:deposit_product_id].to_i if p[:deposit_product_id].present?
      p
    end

    def operational_event_list_json(event)
      {
        id: event.id,
        event_type: event.event_type,
        status: event.status,
        business_date: event.business_date.iso8601,
        channel: event.channel,
        idempotency_key: event.idempotency_key,
        amount_minor_units: event.amount_minor_units,
        currency: event.currency,
        source_account_id: event.source_account_id,
        destination_account_id: event.destination_account_id,
        teller_session_id: event.teller_session_id,
        actor_id: event.actor_id,
        reversal_of_event_id: event.reversal_of_event_id,
        reversed_by_event_id: event.reversed_by_event_id,
        reference_id: event.reference_id,
        created_at: event.created_at.iso8601(3),
        updated_at: event.updated_at.iso8601(3),
        source_account: deposit_account_context_json(event.source_account),
        destination_account: deposit_account_context_json(event.destination_account),
        posting_batch_ids: event.posting_batches.map(&:id),
        journal_entry_ids: event.posting_batches.flat_map { |b| b.journal_entries.map(&:id) }
      }
    end

    def deposit_account_context_json(account)
      return nil if account.nil?

      {
        id: account.id,
        account_number: account.account_number,
        deposit_product_id: account.deposit_product_id,
        product_code: account.product_code,
        product_name: account.deposit_product&.name
      }
    end
  end
end
