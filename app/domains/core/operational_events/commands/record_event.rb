# frozen_string_literal: true

require "digest"

module Core
  module OperationalEvents
    module Commands
      class RecordEvent
        class Error < StandardError; end
        class InvalidRequest < Error; end
        class MismatchedIdempotency < Error
          attr_reader :fingerprint

          def initialize(fingerprint)
            @fingerprint = fingerprint
            super("idempotency_key replay does not match original request fingerprint=#{fingerprint}")
          end
        end

        class PostedReplay < Error
          def initialize(message = "operational event already posted for this idempotency key")
            super(message)
          end
        end

        SLICE_EVENT_TYPES = %w[deposit.accepted].freeze
        CHANNELS = %w[teller api batch system].freeze

        # @return [Hash] `{ outcome: :created|:replay, event: OperationalEvent }`
        def self.call(
          event_type:,
          channel:,
          idempotency_key:,
          amount_minor_units:,
          currency:,
          source_account_id:,
          business_date: nil
        )
          validate_channel!(channel)
          validate_event_type!(event_type)
          validate_deposit_accepted!(amount_minor_units, currency, source_account_id)
          validate_source_account!(source_account_id)

          on_date = business_date || Core::BusinessDate::Services::CurrentBusinessDate.call
          incoming_fp = fingerprint(
            event_type: event_type,
            channel: channel,
            idempotency_key: idempotency_key,
            amount_minor_units: amount_minor_units,
            currency: currency,
            source_account_id: source_account_id
          )

          begin
            Models::OperationalEvent.transaction(requires_new: true) do
              existing = Models::OperationalEvent.lock.find_by(channel: channel, idempotency_key: idempotency_key)
              if existing
                return handle_existing(existing, incoming_fp)
              end

              event = Models::OperationalEvent.create!(
                event_type: event_type,
                status: Models::OperationalEvent::STATUS_PENDING,
                business_date: on_date,
                channel: channel,
                idempotency_key: idempotency_key,
                amount_minor_units: amount_minor_units,
                currency: currency,
                source_account_id: source_account_id
              )
              { outcome: :created, event: event }
            end
          rescue ActiveRecord::RecordNotUnique
            existing = Models::OperationalEvent.find_by!(channel: channel, idempotency_key: idempotency_key)
            handle_existing(existing, incoming_fp)
          end
        end

        def self.fingerprint(event_type:, channel:, idempotency_key:, amount_minor_units:, currency:, source_account_id:)
          payload = {
            event_type: event_type,
            channel: channel,
            idempotency_key: idempotency_key,
            amount_minor_units: amount_minor_units.to_i,
            currency: currency.to_s,
            source_account_id: source_account_id.to_i
          }
          Digest::SHA256.hexdigest(payload.to_json)
        end

        def self.validate_channel!(channel)
          return if CHANNELS.include?(channel.to_s)

          raise InvalidRequest, "channel must be one of: #{CHANNELS.join(", ")}"
        end

        def self.validate_event_type!(event_type)
          return if SLICE_EVENT_TYPES.include?(event_type.to_s)

          raise InvalidRequest, "event_type not supported in slice 1: #{event_type.inspect}"
        end

        def self.validate_deposit_accepted!(amount_minor_units, currency, source_account_id)
          if amount_minor_units.nil? || amount_minor_units.to_i <= 0
            raise InvalidRequest, "amount_minor_units must be a positive integer"
          end
          raise InvalidRequest, "currency is required" if currency.blank?
          raise InvalidRequest, "currency must be USD for slice 1" unless currency.to_s == "USD"
          raise InvalidRequest, "source_account_id is required for deposit.accepted" if source_account_id.blank?
        end

        def self.validate_source_account!(source_account_id)
          acc = Accounts::Models::DepositAccount.find_by(id: source_account_id)
          raise InvalidRequest, "source_account_id not found" if acc.nil?
          raise InvalidRequest, "source account must be open" unless acc.status == Accounts::Models::DepositAccount::STATUS_OPEN
        end

        def self.handle_existing(existing, incoming_fp)
          existing_fp = fingerprint(
            event_type: existing.event_type,
            channel: existing.channel,
            idempotency_key: existing.idempotency_key,
            amount_minor_units: existing.amount_minor_units,
            currency: existing.currency,
            source_account_id: existing.source_account_id
          )
          raise MismatchedIdempotency.new(incoming_fp) if existing_fp != incoming_fp
          raise PostedReplay if existing.status == Models::OperationalEvent::STATUS_POSTED

          { outcome: :replay, event: existing }
        end
        private_class_method :handle_existing
      end
    end
  end
end
