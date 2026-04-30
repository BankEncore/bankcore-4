# frozen_string_literal: true

module Party
  module Models
    class PartyEmail < ApplicationRecord
      self.table_name = "party_emails"

      PURPOSE_PRIMARY = "primary"
      PURPOSE_SECONDARY = "secondary"
      PURPOSES = [ PURPOSE_PRIMARY, PURPOSE_SECONDARY ].freeze

      STATUS_ACTIVE = "active"
      STATUS_INACTIVE = "inactive"
      STATUSES = [ STATUS_ACTIVE, STATUS_INACTIVE ].freeze

      belongs_to :party_record, class_name: "Party::Models::PartyRecord"

      validates :email, :purpose, :status, :effective_on, presence: true
      validates :purpose, inclusion: { in: PURPOSES }
      validates :status, inclusion: { in: STATUSES }

      scope :active, -> { where(status: STATUS_ACTIVE) }

      def summary
        "#{purpose}: #{email}"
      end
    end
  end
end
