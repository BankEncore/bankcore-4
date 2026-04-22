# frozen_string_literal: true

module Party
  module Queries
    class FindParty
      def self.by_id(id)
        Models::PartyRecord.find(id)
      end
    end
  end
end
