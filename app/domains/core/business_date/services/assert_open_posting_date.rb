# frozen_string_literal: true

module Core
  module BusinessDate
    module Services
      # Enforces ADR-0018: new operational / hold activity uses only the current open business day.
      class AssertOpenPostingDate
        def self.call!(date:)
          raise ArgumentError, "date must be a Date" unless date.is_a?(Date)

          current = CurrentBusinessDate.call
          return if date == current

          raise Errors::InvalidPostingBusinessDate,
            "business_date must equal current business date (#{current.iso8601}), was #{date.iso8601}"
        end
      end
    end
  end
end
