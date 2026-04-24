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

        DRAWER_VARIANCE_POSTED = "teller.drawer.variance.posted"
        INTEREST_EVENT_TYPES = %w[interest.accrued interest.posted].freeze

        FINANCIAL_EVENT_TYPES = (
          %w[deposit.accepted withdrawal.posted transfer.completed fee.assessed fee.waived] +
            INTEREST_EVENT_TYPES + [ DRAWER_VARIANCE_POSTED ]
        ).freeze
        CHANNELS = %w[teller api batch system].freeze
        TELLER_CASH_EVENT_TYPES = %w[deposit.accepted withdrawal.posted].freeze

        # @return [Hash] `{ outcome: :created|:replay, event: OperationalEvent }`
        def self.call(
          event_type:,
          channel:,
          idempotency_key:,
          amount_minor_units:,
          currency:,
          source_account_id: nil,
          destination_account_id: nil,
          business_date: nil,
          teller_session_id: nil,
          actor_id: nil,
          reference_id: nil,
          force_nsf_fee: false
        )
          validate_channel!(channel)
          validate_event_type!(event_type)
          validate_financial_amounts!(event_type, amount_minor_units, currency, source_account_id, destination_account_id)
          validate_source_account!(event_type, source_account_id)
          validate_destination_account!(event_type, destination_account_id)
          validate_transfer_distinct!(event_type, source_account_id, destination_account_id)
          validate_withdrawal_available!(event_type, source_account_id, amount_minor_units)
          validate_transfer_available!(event_type, source_account_id, amount_minor_units)
          validate_fee_assessed_available!(event_type, channel, source_account_id, amount_minor_units, force_nsf_fee, reference_id)
          validate_fee_waived!(event_type, source_account_id, amount_minor_units, reference_id)
          validate_interest_system_channel!(event_type, channel)
          validate_interest_posted!(event_type, source_account_id, amount_minor_units, currency, reference_id)
          validate_teller_cash_session!(channel, event_type, teller_session_id)
          validate_drawer_variance!(event_type, channel, amount_minor_units, teller_session_id)

          on_date = business_date || Core::BusinessDate::Services::CurrentBusinessDate.call
          begin
            Core::BusinessDate::Services::AssertOpenPostingDate.call!(date: on_date)
          rescue Core::BusinessDate::Errors::InvalidPostingBusinessDate => e
            raise InvalidRequest, e.message
          end
          incoming_fp = fingerprint_for(
            event_type: event_type,
            channel: channel,
            idempotency_key: idempotency_key,
            amount_minor_units: amount_minor_units,
            currency: currency,
            source_account_id: source_account_id,
            destination_account_id: destination_account_id,
            teller_session_id: teller_session_id,
            reference_id: reference_id
          )

          begin
            Models::OperationalEvent.transaction(requires_new: true) do
              existing = Models::OperationalEvent.lock.find_by(channel: channel, idempotency_key: idempotency_key)
              if existing
                return handle_existing(existing, incoming_fp)
              end

              if event_type.to_s == "fee.waived" && reference_id.present?
                ref_key = reference_id.to_s
                if Models::OperationalEvent.exists?(event_type: "fee.waived", reference_id: ref_key)
                  raise InvalidRequest, "fee waiver already recorded for this assessment"
                end
              end

              if event_type.to_s == "interest.posted" && reference_id.present?
                ref_key = reference_id.to_s
                if Models::OperationalEvent.exists?(event_type: "interest.posted", reference_id: ref_key)
                  raise InvalidRequest, "interest payout already recorded for this accrual"
                end
              end

              if event_type.to_s == DRAWER_VARIANCE_POSTED && teller_session_id.present?
                if Models::OperationalEvent.exists?(event_type: DRAWER_VARIANCE_POSTED, teller_session_id: teller_session_id.to_i)
                  raise InvalidRequest, "drawer variance already recorded for this teller session"
                end
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
                actor_id: actor_id,
                reference_id: reference_id.presence
              )
              { outcome: :created, event: event }
            end
          rescue ActiveRecord::RecordNotUnique
            existing = Models::OperationalEvent.find_by!(channel: channel, idempotency_key: idempotency_key)
            handle_existing(existing, incoming_fp)
          end
        end

        def self.fingerprint_for(event_type:, channel:, idempotency_key:, amount_minor_units:, currency:, source_account_id:,
                                destination_account_id: nil, teller_session_id: nil, reference_id: nil)
          if event_type.to_s == DRAWER_VARIANCE_POSTED
            payload = {
              event_type: event_type.to_s,
              channel: channel.to_s,
              idempotency_key: idempotency_key.to_s,
              amount_minor_units: amount_minor_units.to_i,
              currency: currency.to_s,
              teller_session_id: teller_session_id.to_i
            }
            return Digest::SHA256.hexdigest(payload.to_json)
          end

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
          if event_type.to_s == "fee.waived" && reference_id.present?
            payload[:reference_id] = reference_id.to_s
          end
          if event_type.to_s == "fee.assessed" && reference_id.present?
            payload[:reference_id] = reference_id.to_s
          end
          if event_type.to_s == "interest.posted" && reference_id.present?
            payload[:reference_id] = reference_id.to_s
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
          if event_type.to_s == DRAWER_VARIANCE_POSTED
            if amount_minor_units.nil? || amount_minor_units.to_i == 0
              raise InvalidRequest, "amount_minor_units must be non-zero for teller.drawer.variance.posted"
            end
            raise InvalidRequest, "currency is required" if currency.blank?
            raise InvalidRequest, "currency must be USD" unless currency.to_s == "USD"
            return
          end

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

        def self.validate_source_account!(event_type, source_account_id)
          return if event_type.to_s == DRAWER_VARIANCE_POSTED && source_account_id.blank?

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

        def self.validate_drawer_variance!(event_type, channel, amount_minor_units, teller_session_id)
          return unless event_type.to_s == DRAWER_VARIANCE_POSTED

          unless channel.to_s == "system"
            raise InvalidRequest, "teller.drawer.variance.posted may only use channel system"
          end
          raise InvalidRequest, "teller_session_id is required for teller.drawer.variance.posted" if teller_session_id.blank?

          sess = Teller::Models::TellerSession.find_by(id: teller_session_id.to_i)
          raise InvalidRequest, "teller_session not found" if sess.nil?
          unless sess.status == Teller::Models::TellerSession::STATUS_CLOSED
            raise InvalidRequest, "teller session must be closed before posting drawer variance"
          end
          if sess.variance_minor_units.nil? || sess.variance_minor_units.to_i != amount_minor_units.to_i
            raise InvalidRequest, "amount_minor_units must match teller_sessions.variance_minor_units for this session"
          end
        end
        private_class_method :validate_drawer_variance!

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

        def self.validate_fee_assessed_available!(event_type, channel, source_account_id, amount_minor_units, force_nsf_fee, reference_id)
          return unless event_type.to_s == "fee.assessed"

          if force_nsf_fee
            validate_forced_nsf_fee!(channel, source_account_id, reference_id)
            return
          end

          available = Accounts::Services::AvailableBalanceMinorUnits.call(deposit_account_id: source_account_id)
          raise InvalidRequest, "insufficient available balance" if available < amount_minor_units.to_i
        end
        private_class_method :validate_fee_assessed_available!

        def self.validate_forced_nsf_fee!(channel, source_account_id, reference_id)
          raise InvalidRequest, "forced NSF fee may only use channel system" unless channel.to_s == "system"
          raise InvalidRequest, "reference_id is required for forced NSF fee" if reference_id.blank?

          match = reference_id.to_s.match(/\Ansf_denial:(\d+)\z/)
          raise InvalidRequest, "reference_id must identify an NSF denial event" if match.nil?

          denial = Models::OperationalEvent.find_by(id: match[1].to_i)
          if denial.nil? || denial.event_type != "overdraft.nsf_denied" ||
              denial.status != Models::OperationalEvent::STATUS_POSTED
            raise InvalidRequest, "reference_id must identify a posted overdraft.nsf_denied event"
          end
          unless denial.source_account_id.to_i == source_account_id.to_i
            raise InvalidRequest, "forced NSF fee must match denial source account"
          end
        end
        private_class_method :validate_forced_nsf_fee!

        def self.validate_fee_waived!(event_type, source_account_id, amount_minor_units, reference_id)
          return unless event_type.to_s == "fee.waived"

          raise InvalidRequest, "reference_id is required for fee.waived" if reference_id.blank?

          ref_key = reference_id.to_s
          unless ref_key.match?(/\A\d+\z/)
            raise InvalidRequest, "reference_id must be the numeric id of a fee.assessed event"
          end

          orig = Models::OperationalEvent.find_by(id: ref_key.to_i)
          raise InvalidRequest, "referenced fee assessment not found" if orig.nil?
          unless orig.event_type == "fee.assessed" && orig.status == Models::OperationalEvent::STATUS_POSTED
            raise InvalidRequest, "reference_id must identify a posted fee.assessed event"
          end
          unless orig.source_account_id.to_i == source_account_id.to_i &&
              orig.amount_minor_units.to_i == amount_minor_units.to_i
            raise InvalidRequest, "fee.waived must match original fee account and amount"
          end
        end
        private_class_method :validate_fee_waived!

        def self.validate_interest_system_channel!(event_type, channel)
          return unless INTEREST_EVENT_TYPES.include?(event_type.to_s)

          raise InvalidRequest, "#{event_type} may only use channel system" unless channel.to_s == "system"
        end
        private_class_method :validate_interest_system_channel!

        def self.validate_interest_posted!(event_type, source_account_id, amount_minor_units, currency, reference_id)
          return unless event_type.to_s == "interest.posted"

          raise InvalidRequest, "reference_id is required for interest.posted" if reference_id.blank?

          ref_key = reference_id.to_s
          unless ref_key.match?(/\A\d+\z/)
            raise InvalidRequest, "reference_id must be the numeric id of an interest.accrued event"
          end

          orig = Models::OperationalEvent.find_by(id: ref_key.to_i)
          raise InvalidRequest, "referenced interest accrual not found" if orig.nil?
          unless orig.event_type == "interest.accrued" && orig.status == Models::OperationalEvent::STATUS_POSTED
            raise InvalidRequest, "reference_id must identify a posted interest.accrued event"
          end
          unless orig.source_account_id.to_i == source_account_id.to_i &&
              orig.amount_minor_units.to_i == amount_minor_units.to_i &&
              orig.currency.to_s == currency.to_s
            raise InvalidRequest, "interest.posted must match original accrual account, amount, and currency"
          end
        end
        private_class_method :validate_interest_posted!

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
            teller_session_id: existing.teller_session_id,
            reference_id: existing.reference_id
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
