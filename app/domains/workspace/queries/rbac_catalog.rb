# frozen_string_literal: true

module Workspace
  module Queries
    class RbacCatalog
      def self.roles
        Models::Role.includes(:capabilities).order(:code)
      end

      def self.capabilities
        Models::Capability.includes(:roles).order(:category, :code)
      end

      def self.active_roles
        Models::Role.where(active: true).order(:code)
      end

      def self.active_capabilities
        Models::Capability.where(active: true).order(:category, :code)
      end

      def self.operating_units
        Organization::Models::OperatingUnit.order(:code)
      end
    end
  end
end
