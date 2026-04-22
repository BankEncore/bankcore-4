# frozen_string_literal: true

module Core
  module BusinessDate
    module Services
      class CurrentBusinessDate
        def self.call
          row = Models::BusinessDateSetting.first
          return row.current_business_on if row

          raise Errors::NotSet, "No core_business_date_settings row; seed or run SetBusinessDate"
        end
      end
    end
  end
end
