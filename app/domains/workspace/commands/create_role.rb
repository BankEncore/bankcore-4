# frozen_string_literal: true

module Workspace
  module Commands
    class CreateRole
      class InvalidRequest < StandardError; end

      def self.call(attributes:)
        attrs = attributes.to_h.symbolize_keys
        Models::Role.create!(
          code: attrs.fetch(:code).to_s.strip.downcase,
          name: attrs.fetch(:name).to_s.strip,
          description: attrs[:description],
          active: boolean_value(attrs.fetch(:active, true)),
          system_role: false
        )
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, KeyError => e
        raise InvalidRequest, e.message
      end

      def self.boolean_value(value)
        ActiveModel::Type::Boolean.new.cast(value)
      end
      private_class_method :boolean_value
    end
  end
end
