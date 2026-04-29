# frozen_string_literal: true

module Workspace
  module Commands
    class CreateCapability
      class InvalidRequest < StandardError; end

      def self.call(attributes:)
        attrs = attributes.to_h.symbolize_keys
        Models::Capability.create!(
          code: attrs.fetch(:code).to_s.strip.downcase,
          name: attrs.fetch(:name).to_s.strip,
          category: attrs.fetch(:category).to_s.strip,
          description: attrs[:description],
          active: ActiveModel::Type::Boolean.new.cast(attrs.fetch(:active, true))
        )
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, KeyError => e
        raise InvalidRequest, e.message
      end
    end
  end
end
