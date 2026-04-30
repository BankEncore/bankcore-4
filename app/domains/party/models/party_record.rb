# frozen_string_literal: true

module Party
  module Models
    class PartyRecord < ApplicationRecord
      self.table_name = "party_records"

      INDIVIDUAL = "individual"

      has_one :individual_profile, class_name: "Party::Models::PartyIndividualProfile", dependent: :restrict_with_exception,
        inverse_of: :party_record
      has_many :party_emails, class_name: "Party::Models::PartyEmail", dependent: :restrict_with_exception
      has_many :party_phones, class_name: "Party::Models::PartyPhone", dependent: :restrict_with_exception
      has_many :party_addresses, class_name: "Party::Models::PartyAddress", dependent: :restrict_with_exception
      has_many :party_contact_audits, class_name: "Party::Models::PartyContactAudit", dependent: :restrict_with_exception

      validates :name, presence: true
      validates :party_type, presence: true
    end
  end
end
