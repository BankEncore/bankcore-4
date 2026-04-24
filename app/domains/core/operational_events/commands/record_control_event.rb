# frozen_string_literal: true

require "digest"

module Core
  module OperationalEvents
    module Commands
      # Non-financial operational audit rows (override workflow). No posting batch.
      class RecordControlEvent
        class Error < StandardError; end
        class InvalidRequest < Error; end
        class MismatchedIdempotency < Error
          attr_reader :fingerprint

          def initialize(fingerprint)
            @fingerprint = fingerprint
            super("idempotency_key replay does not match original request fingerprint=#{fingerprint}")
          end
        end

        CONTROL_EVENT_TYPES = %w[override.requested override.approved].freeze

        def self.call(event_type:, channel:, idempotency_key:, reference_id:, actor_id: nil, business_date: nil)
          RecordEvent.validate_channel!(channel)
          type = event_type.to_s
          unless CONTROL_EVENT_TYPES.include?(type)
            raise InvalidRequest, "event_type not supported: #{event_type.inspect}"
          end
          raise InvalidRequest, "reference_id is required" if reference_id.blank?

          on_date = business_date || Core::BusinessDate::Services::CurrentBusinessDate.call
          begin
            Core::BusinessDate::Services::AssertOpenPostingDate.call!(date: on_date)
          rescue Core::BusinessDate::Errors::InvalidPostingBusinessDate => e
            raise InvalidRequest, e.message
          end
          incoming_fp = fingerprint(event_type: type, channel: channel, idempotency_key: idempotency_key,
                                      reference_id: reference_id.to_s, actor_id: actor_id)

          begin
            Models::OperationalEvent.transaction(requires_new: true) do
              existing = Models::OperationalEvent.lock.find_by(channel: channel, idempotency_key: idempotency_key)
              if existing
                return handle_existing(existing, incoming_fp)
              end

              event = Models::OperationalEvent.create!(
                event_type: type,
                status: Models::OperationalEvent::STATUS_POSTED,
                business_date: on_date,
                channel: channel,
                idempotency_key: idempotency_key,
                reference_id: reference_id.to_s,
                actor_id: actor_id,
                amount_minor_units: nil,
                currency: nil,
                source_account_id: nil
              )
              { outcome: :created, event: event }
            end
          rescue ActiveRecord::RecordNotUnique
            existing = Models::OperationalEvent.find_by!(channel: channel, idempotency_key: idempotency_key)
            handle_existing(existing, incoming_fp)
          end
        end

        def self.fingerprint(event_type:, channel:, idempotency_key:, reference_id:, actor_id:)
          payload = {
            event_type: event_type,
            channel: channel.to_s,
            idempotency_key: idempotency_key.to_s,
            reference_id: reference_id,
            actor_id: actor_id&.to_i
          }
          Digest::SHA256.hexdigest(payload.to_json)
        end

        def self.handle_existing(existing, incoming_fp)
          existing_fp = fingerprint(
            event_type: existing.event_type,
            channel: existing.channel,
            idempotency_key: existing.idempotency_key,
            reference_id: existing.reference_id.to_s,
            actor_id: existing.actor_id
          )
          raise MismatchedIdempotency.new(incoming_fp) if existing_fp != incoming_fp

          { outcome: :replay, event: existing }
        end
        private_class_method :handle_existing
      end
    end
  end
end
