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

        NSF_DENIED = "overdraft.nsf_denied"
        CONTROL_EVENT_TYPES = %w[override.requested override.approved overdraft.nsf_denied].freeze

        def self.call(event_type:, channel:, idempotency_key:, reference_id:, actor_id: nil, business_date: nil,
                      amount_minor_units: nil, currency: nil, source_account_id: nil, destination_account_id: nil,
                      operating_unit_id: nil)
          RecordEvent.validate_channel!(channel)
          type = event_type.to_s
          unless CONTROL_EVENT_TYPES.include?(type)
            raise InvalidRequest, "event_type not supported: #{event_type.inspect}"
          end
          raise InvalidRequest, "reference_id is required" if reference_id.blank?
          validate_nsf_denied!(type, amount_minor_units, currency, source_account_id, destination_account_id, reference_id)

          on_date = business_date || Core::BusinessDate::Services::CurrentBusinessDate.call
          begin
            Core::BusinessDate::Services::AssertOpenPostingDate.call!(date: on_date)
          rescue Core::BusinessDate::Errors::InvalidPostingBusinessDate => e
            raise InvalidRequest, e.message
          end
          resolved_operating_unit = resolve_operating_unit(channel, actor_id, operating_unit_id)

          incoming_fp = fingerprint(event_type: type, channel: channel, idempotency_key: idempotency_key,
                                    reference_id: reference_id.to_s, actor_id: actor_id,
                                    amount_minor_units: amount_minor_units, currency: currency,
                                    source_account_id: source_account_id, destination_account_id: destination_account_id,
                                    operating_unit_id: resolved_operating_unit&.id)

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
                amount_minor_units: amount_minor_units,
                currency: currency,
                source_account_id: source_account_id,
                destination_account_id: destination_account_id,
                operating_unit: resolved_operating_unit
              )
              { outcome: :created, event: event }
            end
          rescue ActiveRecord::RecordNotUnique
            existing = Models::OperationalEvent.find_by!(channel: channel, idempotency_key: idempotency_key)
            handle_existing(existing, incoming_fp)
          end
        end

        def self.fingerprint(event_type:, channel:, idempotency_key:, reference_id:, actor_id:,
                             amount_minor_units: nil, currency: nil, source_account_id: nil, destination_account_id: nil,
                             operating_unit_id: nil)
          payload = {
            event_type: event_type,
            channel: channel.to_s,
            idempotency_key: idempotency_key.to_s,
            reference_id: reference_id,
            actor_id: actor_id&.to_i,
            amount_minor_units: amount_minor_units&.to_i,
            currency: currency&.to_s,
            source_account_id: source_account_id&.to_i,
            destination_account_id: destination_account_id&.to_i,
            operating_unit_id: operating_unit_id&.to_i
          }
          Digest::SHA256.hexdigest(payload.to_json)
        end

        def self.resolve_operating_unit(channel, actor_id, operating_unit_id)
          return nil unless RecordEvent::STAFF_CHANNELS.include?(channel.to_s)

          actor = Workspace::Models::Operator.find_by(id: actor_id) if actor_id.present?
          Organization::Services::ResolveOperatingUnit.call(
            operator: actor,
            operating_unit_id: operating_unit_id
          )
        rescue Organization::Services::ResolveOperatingUnit::Error,
          Organization::Services::DefaultOperatingUnit::AmbiguousDefault,
          Organization::Services::DefaultOperatingUnit::NotFound => e
          raise InvalidRequest, e.message
        end
        private_class_method :resolve_operating_unit

        def self.validate_nsf_denied!(type, amount_minor_units, currency, source_account_id, destination_account_id, reference_id)
          return unless type == NSF_DENIED

          if amount_minor_units.nil? || amount_minor_units.to_i <= 0
            raise InvalidRequest, "amount_minor_units must be a positive integer for overdraft.nsf_denied"
          end
          raise InvalidRequest, "currency is required for overdraft.nsf_denied" if currency.blank?
          raise InvalidRequest, "currency must be USD" unless currency.to_s == "USD"
          raise InvalidRequest, "source_account_id is required for overdraft.nsf_denied" if source_account_id.blank?
          unless %w[attempt:withdrawal.posted attempt:transfer.completed].include?(reference_id.to_s)
            raise InvalidRequest, "reference_id must describe the denied attempt type"
          end
          if reference_id.to_s == "attempt:transfer.completed" && destination_account_id.blank?
            raise InvalidRequest, "destination_account_id is required for denied transfer"
          end

          source = Accounts::Models::DepositAccount.find_by(id: source_account_id)
          raise InvalidRequest, "source_account_id not found" if source.nil?
          raise InvalidRequest, "source account must be open" unless source.status == Accounts::Models::DepositAccount::STATUS_OPEN

          return if destination_account_id.blank?

          destination = Accounts::Models::DepositAccount.find_by(id: destination_account_id)
          raise InvalidRequest, "destination_account_id not found" if destination.nil?
          unless destination.status == Accounts::Models::DepositAccount::STATUS_OPEN
            raise InvalidRequest, "destination account must be open"
          end
        end
        private_class_method :validate_nsf_denied!

        def self.handle_existing(existing, incoming_fp)
          existing_fp = fingerprint(
            event_type: existing.event_type,
            channel: existing.channel,
            idempotency_key: existing.idempotency_key,
            reference_id: existing.reference_id.to_s,
            actor_id: existing.actor_id,
            amount_minor_units: existing.amount_minor_units,
            currency: existing.currency,
            source_account_id: existing.source_account_id,
            destination_account_id: existing.destination_account_id,
            operating_unit_id: existing.operating_unit_id
          )
          raise MismatchedIdempotency.new(incoming_fp) if existing_fp != incoming_fp

          { outcome: :replay, event: existing }
        end
        private_class_method :handle_existing
      end
    end
  end
end
