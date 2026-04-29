# frozen_string_literal: true

module Workspace
  module Commands
    class DeactivateOperator
      class InvalidRequest < StandardError; end

      def self.call(operator_id:)
        operator = Models::Operator.find(operator_id)
        operator.update!(active: false)
        operator
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
        raise InvalidRequest, e.message
      end
    end
  end
end
