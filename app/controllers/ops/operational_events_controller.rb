# frozen_string_literal: true

module Ops
  class OperationalEventsController < ApplicationController
    def index
      @query_params = permitted_query_params
      @event_search = Core::OperationalEvents::Queries::ListOperationalEvents.call(**@query_params)
    rescue Core::OperationalEvents::Queries::ListOperationalEvents::InvalidQuery => e
      @error_message = e.message
      @event_search = nil
      render :index, status: :unprocessable_entity
    rescue Core::BusinessDate::Errors::NotSet => e
      @error_message = e.message
      @event_search = nil
      render :index, status: :unprocessable_entity
    end

    def show
      @event = Core::OperationalEvents::Models::OperationalEvent.includes(
        :actor,
        :teller_session,
        { source_account: :deposit_product },
        { destination_account: :deposit_product },
        { posting_batches: { journal_entries: { journal_lines: [ :gl_account, :deposit_account ] } } }
      ).find(params[:id])
    end

    private

    def permitted_query_params
      p = params.permit(
        :business_date, :business_date_from, :business_date_to,
        :source_account_id, :destination_account_id, :status, :event_type, :channel, :actor_id,
        :reference_id, :idempotency_key, :reversal_of_event_id,
        :deposit_product_id, :product_code, :after_id, :limit
      ).to_h.symbolize_keys
      p[:source_account_id] = p[:source_account_id].to_i if p[:source_account_id].present?
      p[:destination_account_id] = p[:destination_account_id].to_i if p[:destination_account_id].present?
      p[:actor_id] = p[:actor_id].to_i if p[:actor_id].present?
      p[:reversal_of_event_id] = p[:reversal_of_event_id].to_i if p[:reversal_of_event_id].present?
      p[:deposit_product_id] = p[:deposit_product_id].to_i if p[:deposit_product_id].present?
      p
    end
  end
end
