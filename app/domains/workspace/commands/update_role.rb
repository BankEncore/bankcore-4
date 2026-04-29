# frozen_string_literal: true

module Workspace
  module Commands
    class UpdateRole
      class InvalidRequest < StandardError; end

      def self.call(role_id:, attributes:)
        role = Models::Role.find(role_id)
        attrs = attributes.to_h.symbolize_keys.slice(:name, :description, :active)
        attrs[:active] = ActiveModel::Type::Boolean.new.cast(attrs[:active]) if attrs.key?(:active)
        role.update!(attrs)
        role
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotFound => e
        raise InvalidRequest, e.message
      end
    end
  end
end
