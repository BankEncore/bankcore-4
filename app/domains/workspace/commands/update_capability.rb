# frozen_string_literal: true

module Workspace
  module Commands
    class UpdateCapability
      class InvalidRequest < StandardError; end

      def self.call(capability_id:, attributes:)
        capability = Models::Capability.find(capability_id)
        attrs = attributes.to_h.symbolize_keys.slice(:name, :category, :description, :active)
        attrs[:active] = ActiveModel::Type::Boolean.new.cast(attrs[:active]) if attrs.key?(:active)
        capability.update!(attrs)
        capability
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
        raise InvalidRequest, e.message
      end
    end
  end
end
