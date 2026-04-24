# frozen_string_literal: true

module Core
  module BusinessDate
    module Errors
      class NotSet < StandardError; end
      class InvalidPostingBusinessDate < StandardError; end
      class UnsafeAdvanceDisallowed < StandardError; end

      # Raised when ADR-0016 EOD readiness is not satisfied for the day being closed.
      class EodNotReady < StandardError
        attr_reader :readiness

        def initialize(message, readiness = nil)
          @readiness = readiness
          super(message)
        end
      end
    end
  end
end
