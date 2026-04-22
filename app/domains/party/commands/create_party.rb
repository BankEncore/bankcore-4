# frozen_string_literal: true

module Party
  module Commands
    class CreateParty
      class UnsupportedPartyType < StandardError; end

      # Slice 1: individual + profile only (GitHub #3).
      def self.call(party_type:, first_name:, last_name:, middle_name: nil, name_suffix: nil, **profile_attrs)
        type = party_type.to_s
        raise UnsupportedPartyType, "slice 1 supports #{Models::PartyRecord::INDIVIDUAL} only" if type != Models::PartyRecord::INDIVIDUAL

        Models::PartyRecord.transaction do
          name = Services::IndividualDisplayName.build(
            first_name: first_name,
            last_name: last_name,
            middle_name: middle_name,
            name_suffix: name_suffix
          )
          record = Models::PartyRecord.create!(party_type: type, name: name)
          Models::PartyIndividualProfile.create!(
            { party_record: record, first_name: first_name, last_name: last_name, middle_name: middle_name,
              name_suffix: name_suffix }.merge(profile_attrs.slice(:preferred_first_name, :preferred_last_name, :date_of_birth, :occupation, :employer))
          )
          record.reload
        end
      end
    end
  end
end
