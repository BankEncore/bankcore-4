# frozen_string_literal: true

module Core
  module BusinessDate
    module Commands
      # Sets or replaces the singleton processing date (bootstrap / ops / tests).
      class SetBusinessDate
        def self.call(on:)
          date = on.is_a?(Date) ? on : Date.iso8601(on.to_s)
          setting = Models::BusinessDateSetting.first_or_initialize
          setting.current_business_on = date
          setting.save!
          setting
        end
      end
    end
  end
end
