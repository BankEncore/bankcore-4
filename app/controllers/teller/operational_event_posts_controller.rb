# frozen_string_literal: true

module Teller
  class OperationalEventPostsController < ApplicationController
    def create
      result = Core::Posting::Commands::PostEvent.call(operational_event_id: params[:id].to_i)
      status = result[:outcome] == :posted ? :created : :ok
      render json: {
        outcome: result[:outcome],
        operational_event_id: result[:event].id
      }, status: status
    rescue Core::Posting::Commands::PostEvent::NotFound
      render json: { error: "not_found" }, status: :not_found
    rescue Core::Posting::Commands::PostEvent::InvalidState => e
      render json: { error: "invalid_state", message: e.message }, status: :unprocessable_entity
    end
  end
end
