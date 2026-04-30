# frozen_string_literal: true

module Party
  module Models
    class PartyAddress < ApplicationRecord
      self.table_name = "party_addresses"

      PURPOSE_RESIDENTIAL = "residential"
      PURPOSE_MAILING = "mailing"
      PURPOSES = [ PURPOSE_RESIDENTIAL, PURPOSE_MAILING ].freeze

      STATUS_ACTIVE = "active"
      STATUS_INACTIVE = "inactive"
      STATUSES = [ STATUS_ACTIVE, STATUS_INACTIVE ].freeze

      belongs_to :party_record, class_name: "Party::Models::PartyRecord"

      validates :line1, :city, :region, :postal_code, :country, :purpose, :status, :effective_on, presence: true
      validates :purpose, inclusion: { in: PURPOSES }
      validates :status, inclusion: { in: STATUSES }

      scope :active, -> { where(status: STATUS_ACTIVE) }

      def summary
        parts = [ line1, line2, city, region, postal_code, country ].compact_blank
        "#{purpose}: #{parts.join(', ')}"
      end
    end
  end
end
