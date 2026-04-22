# frozen_string_literal: true

module Core
  module BusinessDate
    module Commands
      # Moves the singleton processing date forward by one calendar day.
      class AdvanceBusinessDate
        def self.call
          setting = Models::BusinessDateSetting.singleton
          setting.update!(current_business_on: setting.current_business_on + 1.day)
          setting
        end
      end
    end
  end
end
