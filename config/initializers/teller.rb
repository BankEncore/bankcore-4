# frozen_string_literal: true

# Teller workspace / session policy. See docs/adr/0014-teller-sessions-and-control-events.md.
Rails.application.config.x.teller ||= ActiveSupport::OrderedOptions.new
Rails.application.config.x.teller.variance_threshold_minor_units =
  ENV.fetch("TELLER_VARIANCE_THRESHOLD_MINOR_UNITS", "0").to_i
