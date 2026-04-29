# frozen_string_literal: true

module Workspace
  module Commands
    class UpdateRoleCapabilities
      class InvalidRequest < StandardError; end

      def self.call(role_id:, capability_ids:)
        role = Models::Role.find(role_id)
        ids = Array(capability_ids).reject(&:blank?).map(&:to_i).uniq
        capabilities = Models::Capability.where(id: ids).to_a
        raise InvalidRequest, "Unknown capability selected" unless capabilities.size == ids.size

        Models::RoleCapability.transaction do
          role.role_capabilities.where.not(capability_id: ids).delete_all
          ids.each do |capability_id|
            role.role_capabilities.find_or_create_by!(capability_id: capability_id)
          end
        end

        role.reload
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
        raise InvalidRequest, e.message
      end
    end
  end
end
