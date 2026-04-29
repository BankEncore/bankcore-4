# frozen_string_literal: true

module Workspace
  module Commands
    class UpdateOperator
      class InvalidRequest < StandardError; end

      def self.call(operator_id:, attributes:)
        operator = Models::Operator.find(operator_id)
        attrs = attributes.to_h.symbolize_keys.slice(:display_name, :role, :active, :default_operating_unit_id)
        operator.update!(attrs)
        operator
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
        raise InvalidRequest, e.message
      end
    end
  end
end
