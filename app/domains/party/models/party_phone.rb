# frozen_string_literal: true

module Party
  module Models
    class PartyPhone < ApplicationRecord
      self.table_name = "party_phones"

      PURPOSE_MOBILE = "mobile"
      PURPOSE_HOME = "home"
      PURPOSE_WORK = "work"
      PURPOSES = [ PURPOSE_MOBILE, PURPOSE_HOME, PURPOSE_WORK ].freeze

      STATUS_ACTIVE = "active"
      STATUS_INACTIVE = "inactive"
      STATUSES = [ STATUS_ACTIVE, STATUS_INACTIVE ].freeze

      belongs_to :party_record, class_name: "Party::Models::PartyRecord"

      validates :phone_number, :purpose, :status, :effective_on, presence: true
      validates :purpose, inclusion: { in: PURPOSES }
      validates :status, inclusion: { in: STATUSES }

      scope :active, -> { where(status: STATUS_ACTIVE) }

      def summary
        "#{purpose}: #{phone_number}"
      end
    end
  end
end
