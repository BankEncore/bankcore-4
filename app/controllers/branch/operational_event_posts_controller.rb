# frozen_string_literal: true

module Branch
  class OperationalEventPostsController < ApplicationController
    def create
      result = Core::Posting::Commands::PostEvent.call(operational_event_id: params[:id].to_i)
      redirect_to branch_event_path(result[:event]),
        notice: "Posted operational event ##{result[:event].id} (#{result[:outcome]})."
    rescue Core::Posting::Commands::PostEvent::NotFound
      redirect_to branch_path, alert: "Operational event not found."
    rescue Core::Posting::Commands::PostEvent::InvalidState => e
      redirect_to branch_event_path(params[:id]), alert: e.message
    end
  end
end
