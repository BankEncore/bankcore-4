# frozen_string_literal: true

module Teller
  # Style-A JSON workspace. CSRF is not applied on ActionController::API; protect this
  # surface in production with mutual TLS, network policy, and/or API authentication.
  class ApplicationController < ActionController::API
  end
end
