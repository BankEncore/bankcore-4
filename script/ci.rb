# frozen_string_literal: true

# Loaded by bin/ci (host Ruby 3.4+ or via docker compose run web …).
require_relative "../config/boot"
require "active_support/continuous_integration"

CI = ActiveSupport::ContinuousIntegration
require_relative "../config/ci.rb"
