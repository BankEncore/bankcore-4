# frozen_string_literal: true

module Workspace
  module Authorization
    module Authorizer
      def self.require_capability!(actor_id:, capability_code:, scope: nil)
        actor = Models::Operator.find_by(id: actor_id)
        unless actor&.active?
          raise Forbidden, "actor must be an active operator"
        end

        return actor if CapabilityResolver.has_capability?(operator: actor, capability_code: capability_code, scope: scope)

        raise Forbidden, "operator is not authorized for #{capability_code}"
      end
    end
  end
end
