# frozen_string_literal: true

module Branch
  class ApplicationController < Internal::ApplicationController
    before_action :require_branch_operator!

    private

    def default_idempotency_key(prefix)
      "#{prefix}-#{SecureRandom.hex(8)}"
    end

    def post_event_if_requested(event, record_and_post)
      return nil unless ActiveModel::Type::Boolean.new.cast(record_and_post)

      Core::Posting::Commands::PostEvent.call(operational_event_id: event.id).tap { event.reload }
    end

    def parse_optional_integer(value)
      value.presence&.to_i
    end
  end
end
