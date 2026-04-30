# frozen_string_literal: true

module Party
  module Queries
    class PartyContactSummary
      Result = Data.define(:emails, :phones, :addresses, :audits)

      def self.call(party_record_id:)
        party = Models::PartyRecord.find(party_record_id)
        Result.new(
          emails: party.party_emails.active.order(:purpose, :id).to_a,
          phones: party.party_phones.active.order(:purpose, :id).to_a,
          addresses: party.party_addresses.active.order(:purpose, :id).to_a,
          audits: party.party_contact_audits.order(created_at: :desc, id: :desc).limit(20).to_a
        )
      end
    end
  end
end
