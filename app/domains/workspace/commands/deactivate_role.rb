# frozen_string_literal: true

module Workspace
  module Commands
    class DeactivateRole
      class InvalidRequest < StandardError; end

      def self.call(role_id:)
        role = Models::Role.find(role_id)
        raise InvalidRequest, "System roles cannot be deactivated" if role.system_role?

        role.update!(active: false)
        role
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
        raise InvalidRequest, e.message
      end
    end
  end
end
