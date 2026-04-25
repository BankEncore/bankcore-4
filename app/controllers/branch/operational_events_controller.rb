# frozen_string_literal: true

module Branch
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
        :source_account,
        :destination_account,
        :teller_session,
        :actor,
        :reversal_of_event,
        { posting_batches: :journal_entries }
      ).find(params[:id])
    end

    private

    def permitted_query_params
      p = params.permit(
        :business_date, :business_date_from, :business_date_to,
        :source_account_id, :destination_account_id, :status, :event_type, :channel, :actor_id,
        :after_id, :limit
      ).to_h.symbolize_keys
      p[:source_account_id] = p[:source_account_id].to_i if p[:source_account_id].present?
      p[:destination_account_id] = p[:destination_account_id].to_i if p[:destination_account_id].present?
      p[:actor_id] = p[:actor_id].to_i if p[:actor_id].present?
      p
    end
  end
end
