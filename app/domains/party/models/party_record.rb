# frozen_string_literal: true

module Party
  module Models
    class PartyRecord < ApplicationRecord
      self.table_name = "party_records"

      INDIVIDUAL = "individual"

      has_one :individual_profile, class_name: "Party::Models::PartyIndividualProfile", dependent: :restrict_with_exception,
        inverse_of: :party_record

      validates :name, presence: true
      validates :party_type, presence: true
    end
  end
end
