# frozen_string_literal: true

module Workspace
  module Commands
    class DeactivateOperatorRoleAssignment
      class InvalidRequest < StandardError; end

      def self.call(assignment_id:)
        assignment = Models::OperatorRoleAssignment.find(assignment_id)
        assignment.update!(active: false)
        assignment
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
        raise InvalidRequest, e.message
      end
    end
  end
end
