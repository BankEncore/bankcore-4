# frozen_string_literal: true

module Teller
  class EventTypesController < ApplicationController
    def index
      render json: { event_types: Core::OperationalEvents::EventCatalog.as_api_array }
    end
  end
end
