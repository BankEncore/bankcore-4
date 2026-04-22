# frozen_string_literal: true

module Party
  module Models
    class PartyIndividualProfile < ApplicationRecord
      self.table_name = "party_individual_profiles"

      belongs_to :party_record, class_name: "Party::Models::PartyRecord"
    end
  end
end
