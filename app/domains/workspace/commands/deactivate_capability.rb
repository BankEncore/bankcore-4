# frozen_string_literal: true

module Workspace
  module Commands
    class DeactivateCapability
      class InvalidRequest < StandardError; end

      def self.call(capability_id:)
        capability = Models::Capability.find(capability_id)
        capability.update!(active: false)
        capability
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
        raise InvalidRequest, e.message
      end
    end
  end
end
