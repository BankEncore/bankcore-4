# frozen_string_literal: true

module Workspace
  module Queries
    class OperatorDirectory
      def self.call(search: nil, status: nil)
        scope = Models::Operator
          .includes(:credential, :default_operating_unit, operator_role_assignments: :role)
          .order(:display_name, :id)

        case status.to_s
        when "active"
          scope = scope.where(active: true)
        when "inactive"
          scope = scope.where(active: false)
        end

        if search.present?
          term = "%#{search.to_s.strip.downcase}%"
          scope = scope.left_joins(:credential).where(
            "lower(operators.display_name) LIKE :term OR lower(operator_credentials.username) LIKE :term",
            term: term
          )
        end

        scope
      end
    end
  end
end
