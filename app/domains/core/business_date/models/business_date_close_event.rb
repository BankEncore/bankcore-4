# frozen_string_literal: true

module Core
  module BusinessDate
    module Models
      class BusinessDateCloseEvent < ApplicationRecord
        self.table_name = "core_business_date_close_events"

        belongs_to :closed_by_operator, class_name: "Workspace::Models::Operator", optional: true

        validates :closed_on, presence: true
        validates :closed_at, presence: true
      end
    end
  end
end
