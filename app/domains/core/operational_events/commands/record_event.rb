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

        FINANCIAL_EVENT_TYPES = %w[deposit.accepted withdrawal.posted transfer.completed].freeze
        CHANNELS = %w[teller api batch system].freeze
        TELLER_CASH_EVENT_TYPES = %w[deposit.accepted withdrawal.posted].freeze

        # @return [Hash] `{ outcome: :created|:replay, event: OperationalEvent }`
        def self.call(
          event_type:,
          channel:,
          idempotency_key:,
          amount_minor_units:,
          currency:,
          source_account_id:,
          destination_account_id: nil,
          business_date: nil,
          teller_session_id: nil,
          actor_id: nil
        )
          validate_channel!(channel)
          validate_event_type!(event_type)
          validate_financial_amounts!(event_type, amount_minor_units, currency, source_account_id, destination_account_id)
          validate_source_account!(source_account_id)
          validate_destination_account!(event_type, destination_account_id)
          validate_transfer_distinct!(event_type, source_account_id, destination_account_id)
          validate_withdrawal_available!(event_type, source_account_id, amount_minor_units)
          validate_transfer_available!(event_type, source_account_id, amount_minor_units)
          validate_teller_cash_session!(channel, event_type, teller_session_id)

          on_date = business_date || Core::BusinessDate::Services::CurrentBusinessDate.call
          incoming_fp = fingerprint_for(
            event_type: event_type,
            channel: channel,
            idempotency_key: idempotency_key,
            amount_minor_units: amount_minor_units,
            currency: currency,
            source_account_id: source_account_id,
            destination_account_id: destination_account_id,
            teller_session_id: teller_session_id
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
                source_account_id: source_account_id,
                destination_account_id: destination_account_id,
                teller_session_id: teller_session_id,
                actor_id: actor_id
              )
              { outcome: :created, event: event }
            end
          rescue ActiveRecord::RecordNotUnique
            existing = Models::OperationalEvent.find_by!(channel: channel, idempotency_key: idempotency_key)
            handle_existing(existing, incoming_fp)
          end
        end

        def self.fingerprint_for(event_type:, channel:, idempotency_key:, amount_minor_units:, currency:, source_account_id:,
                                destination_account_id: nil, teller_session_id: nil)
          payload = {
            event_type: event_type.to_s,
            channel: channel.to_s,
            idempotency_key: idempotency_key.to_s,
            amount_minor_units: amount_minor_units.to_i,
            currency: currency.to_s,
            source_account_id: source_account_id.to_i
          }
          if event_type.to_s == "transfer.completed"
            payload[:destination_account_id] = destination_account_id.to_i
          end
          if teller_cash_session_gate?(channel, event_type)
            payload[:teller_session_id] = teller_session_id&.to_i
          end
          Digest::SHA256.hexdigest(payload.to_json)
        end

        def self.validate_channel!(channel)
          return if CHANNELS.include?(channel.to_s)

          raise InvalidRequest, "channel must be one of: #{CHANNELS.join(", ")}"
        end

        def self.validate_event_type!(event_type)
          return if FINANCIAL_EVENT_TYPES.include?(event_type.to_s)

          raise InvalidRequest, "event_type not supported: #{event_type.inspect}"
        end

        def self.validate_financial_amounts!(event_type, amount_minor_units, currency, source_account_id, destination_account_id)
          if amount_minor_units.nil? || amount_minor_units.to_i <= 0
            raise InvalidRequest, "amount_minor_units must be a positive integer"
          end
          raise InvalidRequest, "currency is required" if currency.blank?
          raise InvalidRequest, "currency must be USD" unless currency.to_s == "USD"
          raise InvalidRequest, "source_account_id is required" if source_account_id.blank?
          if event_type.to_s == "transfer.completed" && destination_account_id.blank?
            raise InvalidRequest, "destination_account_id is required for transfer.completed"
          end
        end

        def self.validate_source_account!(source_account_id)
          acc = Accounts::Models::DepositAccount.find_by(id: source_account_id)
          raise InvalidRequest, "source_account_id not found" if acc.nil?
          raise InvalidRequest, "source account must be open" unless acc.status == Accounts::Models::DepositAccount::STATUS_OPEN
        end

        def self.validate_destination_account!(event_type, destination_account_id)
          return unless event_type.to_s == "transfer.completed"

          acc = Accounts::Models::DepositAccount.find_by(id: destination_account_id)
          raise InvalidRequest, "destination_account_id not found" if acc.nil?
          raise InvalidRequest, "destination account must be open" unless acc.status == Accounts::Models::DepositAccount::STATUS_OPEN
        end

        def self.validate_transfer_distinct!(event_type, source_account_id, destination_account_id)
          return unless event_type.to_s == "transfer.completed"
          return if source_account_id.to_i != destination_account_id.to_i

          raise InvalidRequest, "transfer requires distinct source and destination accounts"
        end

        def self.validate_withdrawal_available!(event_type, source_account_id, amount_minor_units)
          return unless event_type.to_s == "withdrawal.posted"

          available = Accounts::Services::AvailableBalanceMinorUnits.call(deposit_account_id: source_account_id)
          raise InvalidRequest, "insufficient available balance" if available < amount_minor_units.to_i
        end

        def self.validate_transfer_available!(event_type, source_account_id, amount_minor_units)
          return unless event_type.to_s == "transfer.completed"

          available = Accounts::Services::AvailableBalanceMinorUnits.call(deposit_account_id: source_account_id)
          raise InvalidRequest, "insufficient available balance" if available < amount_minor_units.to_i
        end

        def self.validate_teller_cash_session!(channel, event_type, teller_session_id)
          return unless teller_cash_session_gate?(channel, event_type)

          if teller_session_id.blank?
            raise InvalidRequest, "teller_session_id is required for #{event_type} on teller channel"
          end

          session = Teller::Models::TellerSession.find_by(id: teller_session_id.to_i)
          raise InvalidRequest, "teller_session not found" if session.nil?
          unless session.status == Teller::Models::TellerSession::STATUS_OPEN
            raise InvalidRequest, "teller session must be open"
          end
        end
        private_class_method :validate_teller_cash_session!

        def self.teller_cash_session_gate?(channel, event_type)
          Rails.application.config.x.teller.require_open_session_for_cash &&
            channel.to_s == "teller" &&
            TELLER_CASH_EVENT_TYPES.include?(event_type.to_s)
        end
        private_class_method :teller_cash_session_gate?

        def self.handle_existing(existing, incoming_fp)
          existing_fp = fingerprint_for(
            event_type: existing.event_type,
            channel: existing.channel,
            idempotency_key: existing.idempotency_key,
            amount_minor_units: existing.amount_minor_units,
            currency: existing.currency,
            source_account_id: existing.source_account_id,
            destination_account_id: existing.destination_account_id,
            teller_session_id: existing.teller_session_id
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
