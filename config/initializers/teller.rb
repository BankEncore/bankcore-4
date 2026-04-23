# frozen_string_literal: true

# Teller workspace / session policy. See docs/adr/0014-teller-sessions-and-control-events.md.
Rails.application.config.x.teller ||= ActiveSupport::OrderedOptions.new
Rails.application.config.x.teller.variance_threshold_minor_units =
  ENV.fetch("TELLER_VARIANCE_THRESHOLD_MINOR_UNITS", "0").to_i

# When true, teller-channel deposit.accepted / withdrawal.posted require an open teller_session_id (ADR-0014).
Rails.application.config.x.teller.require_open_session_for_cash =
  !%w[false 0 no].include?(ENV.fetch("TELLER_REQUIRE_OPEN_SESSION_FOR_CASH", "true").to_s.downcase)
