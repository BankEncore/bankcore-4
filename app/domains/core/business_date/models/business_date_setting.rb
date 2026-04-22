# frozen_string_literal: true

module Core
  module BusinessDate
    module Models
      # Single-row institution processing calendar (slice 1). See GitHub Slice 1 #2.
      class BusinessDateSetting < ApplicationRecord
        self.table_name = "core_business_date_settings"

        validates :current_business_on, presence: true

        def self.singleton
          first || raise(Core::BusinessDate::Errors::NotSet, "core_business_date_settings has no row; run seeds or SetBusinessDate")
        end
      end
    end
  end
end
