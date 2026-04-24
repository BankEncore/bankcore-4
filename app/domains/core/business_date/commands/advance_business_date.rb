# frozen_string_literal: true

module Core
  module BusinessDate
    module Commands
      # Moves the singleton processing date forward by one calendar day.
      # ADR-0018: disallowed outside test; production uses CloseBusinessDate after EOD readiness.
      class AdvanceBusinessDate
        def self.call
          unless Rails.env.test?
            raise Errors::UnsafeAdvanceDisallowed,
              "AdvanceBusinessDate is test-only; use Core::BusinessDate::Commands::CloseBusinessDate after EOD readiness"
          end

          setting = Models::BusinessDateSetting.singleton
          setting.update!(current_business_on: setting.current_business_on + 1.day)
          setting
        end
      end
    end
  end
end
