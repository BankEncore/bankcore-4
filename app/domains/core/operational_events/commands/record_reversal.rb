# frozen_string_literal: true

require "digest"

module Core
  module OperationalEvents
    module Commands
      class RecordReversal
        class Error < StandardError; end
        class InvalidRequest < Error; end
        class NotFound < Error; end
        class MismatchedIdempotency < Error
          attr_reader :fingerprint

          def initialize(fingerprint)
            @fingerprint = fingerprint
            super("idempotency_key replay does not match original request fingerprint=#{fingerprint}")
          end
        end

        class PostedReplay < Error
        end

        REVERSIBLE_TYPES = %w[
          deposit.accepted
          check.deposit.accepted
          withdrawal.posted
          transfer.completed
          interest.accrued
          interest.posted
        ].freeze
        STAFF_CHANNELS = %w[teller branch].freeze

        def self.call(original_operational_event_id:, channel:, idempotency_key:, business_date: nil, actor_id: nil,
                      operating_unit_id: nil)
          RecordEvent.validate_channel!(channel)
          resolved_operating_unit = resolve_operating_unit(channel, actor_id, operating_unit_id)
          authorize_staff_reversal!(channel, actor_id, resolved_operating_unit)

          original = Models::OperationalEvent.find_by(id: original_operational_event_id)
          raise NotFound, "original_operational_event_id=#{original_operational_event_id}" if original.nil?
          unless original.status == Models::OperationalEvent::STATUS_POSTED
            raise InvalidRequest, "original event must be posted"
          end
          unless REVERSIBLE_TYPES.include?(original.event_type)
            raise InvalidRequest, "event_type cannot be reversed: #{original.event_type.inspect}"
          end
          if Models::OperationalEvent.exists?(reversal_of_event_id: original.id)
            raise InvalidRequest, "original event already has a reversal"
          end
          if %w[deposit.accepted check.deposit.accepted].include?(original.event_type.to_s) &&
              Accounts::Models::Hold.exists?(
                placed_for_operational_event_id: original.id,
                status: Accounts::Models::Hold::STATUS_ACTIVE
              )
            raise InvalidRequest, "active deposit-linked holds must be released before reversing this deposit"
          end
          if original.event_type == "interest.accrued" &&
              Models::OperationalEvent.exists?(
                event_type: "interest.posted",
                status: Models::OperationalEvent::STATUS_POSTED,
                reference_id: original.id.to_s
              )
            raise InvalidRequest, "linked interest payout must be resolved before reversing this accrual"
          end

          on_date = business_date || Core::BusinessDate::Services::CurrentBusinessDate.call
          begin
            Core::BusinessDate::Services::AssertOpenPostingDate.call!(date: on_date)
          rescue Core::BusinessDate::Errors::InvalidPostingBusinessDate => e
            raise InvalidRequest, e.message
          end
          incoming_fp = fingerprint(original_operational_event_id: original_operational_event_id, channel: channel,
                                    idempotency_key: idempotency_key, operating_unit_id: resolved_operating_unit&.id)

          begin
            Models::OperationalEvent.transaction(requires_new: true) do
              existing = Models::OperationalEvent.lock.find_by(channel: channel, idempotency_key: idempotency_key)
              if existing
                return handle_existing(existing, incoming_fp, original_operational_event_id)
              end

              event = Models::OperationalEvent.create!(
                event_type: "posting.reversal",
                status: Models::OperationalEvent::STATUS_PENDING,
                business_date: on_date,
                channel: channel,
                idempotency_key: idempotency_key,
                amount_minor_units: original.amount_minor_units,
                currency: original.currency,
                source_account_id: original.source_account_id,
                destination_account_id: original.destination_account_id,
                reversal_of_event_id: original.id,
                actor_id: actor_id,
                operating_unit: resolved_operating_unit
              )
              { outcome: :created, event: event }
            end
          rescue ActiveRecord::RecordNotUnique
            existing = Models::OperationalEvent.find_by!(channel: channel, idempotency_key: idempotency_key)
            handle_existing(existing, incoming_fp, original_operational_event_id)
          end
        end

        def self.fingerprint(original_operational_event_id:, channel:, idempotency_key:, operating_unit_id: nil)
          payload = {
            event_type: "posting.reversal",
            channel: channel.to_s,
            idempotency_key: idempotency_key.to_s,
            original_operational_event_id: original_operational_event_id.to_i,
            operating_unit_id: operating_unit_id&.to_i
          }
          Digest::SHA256.hexdigest(payload.to_json)
        end

        def self.handle_existing(existing, incoming_fp, original_operational_event_id)
          raise InvalidRequest, "not a reversal event" unless existing.event_type == "posting.reversal"
          raise InvalidRequest, "reversal original mismatch" if existing.reversal_of_event_id != original_operational_event_id

          existing_fp = fingerprint(
            original_operational_event_id: existing.reversal_of_event_id,
            channel: existing.channel,
            idempotency_key: existing.idempotency_key,
            operating_unit_id: existing.operating_unit_id
          )
          raise MismatchedIdempotency.new(incoming_fp) if existing_fp != incoming_fp
          raise PostedReplay if existing.status == Models::OperationalEvent::STATUS_POSTED

          { outcome: :replay, event: existing }
        end
        private_class_method :handle_existing

        def self.resolve_operating_unit(channel, actor_id, operating_unit_id)
          return nil unless STAFF_CHANNELS.include?(channel.to_s)

          actor = Workspace::Models::Operator.find_by(id: actor_id) if actor_id.present?
          Organization::Services::ResolveOperatingUnit.call(operator: actor, operating_unit_id: operating_unit_id)
        rescue Organization::Services::ResolveOperatingUnit::Error,
          Organization::Services::DefaultOperatingUnit::AmbiguousDefault,
          Organization::Services::DefaultOperatingUnit::NotFound => e
          raise InvalidRequest, e.message
        end
        private_class_method :resolve_operating_unit

        def self.authorize_staff_reversal!(channel, actor_id, operating_unit)
          return unless STAFF_CHANNELS.include?(channel.to_s)

          Workspace::Authorization::Authorizer.require_capability!(
            actor_id: actor_id,
            capability_code: Workspace::Authorization::CapabilityRegistry::REVERSAL_CREATE,
            scope: operating_unit
          )
        end
        private_class_method :authorize_staff_reversal!
      end
    end
  end
end
