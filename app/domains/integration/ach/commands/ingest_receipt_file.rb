# frozen_string_literal: true

module Integration
  module Ach
    module Commands
      class IngestReceiptFile
        class Error < StandardError; end
        class InvalidRequest < Error; end

        EVENT_TYPE = "ach.credit.received"
        CHANNEL = "batch"
        CURRENCY = "USD"

        Result = Data.define(:business_date, :file_id, :outcomes) do
          def counts
            outcomes.each_with_object(Hash.new(0)) { |row, memo| memo[row.fetch(:outcome)] += 1 }
          end
        end

        def self.call(file_id:, batches:, business_date: nil, preview: false)
          normalized_file_id = normalize_required_identifier(file_id, "file_id")
          normalized_batches = normalize_batches!(batches)
          on_date = normalize_business_date(business_date)

          outcomes = normalized_batches.flat_map do |batch|
            batch.fetch(:items).map do |item|
              process_item(
                file_id: normalized_file_id,
                batch_id: batch.fetch(:batch_id),
                item: item,
                business_date: on_date,
                preview: preview
              )
            end
          end

          Result.new(business_date: on_date, file_id: normalized_file_id, outcomes: outcomes)
        end

        def self.process_item(file_id:, batch_id:, item:, business_date:, preview:)
          normalized = normalize_item(item, file_id: file_id, batch_id: batch_id)
          return invalid_item_row(file_id: file_id, batch_id: batch_id, item: item, message: normalized.fetch(:message)) unless normalized.fetch(:valid)

          item_attrs = normalized.fetch(:attrs)
          account = Accounts::Queries::FindDepositAccountByAccountNumber.call(account_number: item_attrs.fetch(:account_number))
          return item_row(item_attrs, outcome: :account_not_found, message: "deposit account not found") if account.nil?
          if account.status != Accounts::Models::DepositAccount::STATUS_OPEN
            return item_row(item_attrs, deposit_account_id: account.id, outcome: :account_closed, message: "deposit account is not open")
          end

          return preview_row(item_attrs, account: account) if preview

          record_and_post(item_attrs, account: account, business_date: business_date)
        end
        private_class_method :process_item

        def self.record_and_post(item_attrs, account:, business_date:)
          existing = existing_event(item_attrs.fetch(:idempotency_key))
          if existing
            if material_mismatch?(existing, item_attrs: item_attrs, account: account, business_date: business_date)
              return item_row(
                item_attrs,
                deposit_account_id: account.id,
                event: existing,
                outcome: :idempotency_mismatch,
                message: "ACH credit idempotency key replay does not match original item"
              )
            end
            return item_row(item_attrs, deposit_account_id: account.id, event: existing, outcome: :already_posted, message: outcome_message(:already_posted)) if existing.status == Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED

            post_result = Core::Posting::Commands::PostEvent.call(operational_event_id: existing.id)
            outcome = post_result.fetch(:outcome) == :already_posted ? :already_posted : :pending_posted
            return item_row(item_attrs, deposit_account_id: account.id, event: existing.reload, outcome: outcome, message: outcome_message(outcome))
          end

          result = Core::OperationalEvents::Commands::RecordEvent.call(
            event_type: EVENT_TYPE,
            channel: CHANNEL,
            idempotency_key: item_attrs.fetch(:idempotency_key),
            amount_minor_units: item_attrs.fetch(:amount_minor_units),
            currency: item_attrs.fetch(:currency),
            source_account_id: account.id,
            business_date: business_date,
            reference_id: item_attrs.fetch(:reference_id)
          )
          event = result.fetch(:event)
          Core::Posting::Commands::PostEvent.call(operational_event_id: event.id)

          item_row(item_attrs, deposit_account_id: account.id, event: event.reload, outcome: :posted, message: outcome_message(:posted))
        rescue Core::OperationalEvents::Commands::RecordEvent::PostedReplay
          existing = existing_event(item_attrs.fetch(:idempotency_key))
          item_row(item_attrs, deposit_account_id: account.id, event: existing, outcome: :already_posted, message: "ACH credit was already posted")
        rescue Core::OperationalEvents::Commands::RecordEvent::MismatchedIdempotency => e
          existing = existing_event(item_attrs.fetch(:idempotency_key))
          item_row(
            item_attrs,
            deposit_account_id: account.id,
            event: existing,
            outcome: :idempotency_mismatch,
            message: e.message
          )
        rescue Core::Posting::Commands::PostEvent::Error, ActiveRecord::RecordNotFound => e
          existing = existing_event(item_attrs.fetch(:idempotency_key))
          item_row(
            item_attrs,
            deposit_account_id: account.id,
            event: existing,
            outcome: :posting_failed,
            message: e.message
          )
        end
        private_class_method :record_and_post

        def self.material_mismatch?(event, item_attrs:, account:, business_date:)
          event.event_type != EVENT_TYPE ||
            event.channel != CHANNEL ||
            event.source_account_id.to_i != account.id ||
            event.amount_minor_units.to_i != item_attrs.fetch(:amount_minor_units) ||
            event.currency.to_s != item_attrs.fetch(:currency) ||
            event.business_date != business_date ||
            event.reference_id.to_s != item_attrs.fetch(:reference_id)
        end
        private_class_method :material_mismatch?

        def self.normalize_batches!(batches)
          raise InvalidRequest, "batches is required" unless batches.respond_to?(:map)

          normalized = batches.map.with_index do |batch, index|
            values = batch.respond_to?(:to_h) ? batch.to_h.with_indifferent_access : {}
            batch_id = normalize_required_identifier(values[:batch_id], "batches[#{index}].batch_id")
            items = values[:items]
            unless items.respond_to?(:map)
              raise InvalidRequest, "batches[#{index}].items is required"
            end

            { batch_id: batch_id, items: items }
          end
          raise InvalidRequest, "batches is required" if normalized.empty?

          normalized
        end
        private_class_method :normalize_batches!

        def self.normalize_item(item, file_id:, batch_id:)
          values = item.respond_to?(:to_h) ? item.to_h.with_indifferent_access : {}
          item_id = normalize_required_identifier(values[:item_id], "item_id")
          account_number = normalize_required_account_number(values[:account_number])
          amount = normalize_amount(values[:amount_minor_units])
          currency = normalize_currency(values[:currency])
          reference_id = reference_id(file_id: file_id, batch_id: batch_id, item_id: item_id)
          idempotency_key = idempotency_key(file_id: file_id, batch_id: batch_id, item_id: item_id)

          {
            valid: true,
            attrs: {
              file_id: file_id,
              batch_id: batch_id,
              item_id: item_id,
              account_number: account_number,
              amount_minor_units: amount,
              currency: currency,
              reference_id: reference_id,
              idempotency_key: idempotency_key
            }
          }
        rescue InvalidRequest => e
          { valid: false, message: e.message }
        end
        private_class_method :normalize_item

        def self.normalize_business_date(business_date)
          on_date = if business_date.present?
            business_date.is_a?(Date) ? business_date : Date.iso8601(business_date.to_s)
          else
            Core::BusinessDate::Services::CurrentBusinessDate.call
          end
          Core::BusinessDate::Services::AssertOpenPostingDate.call!(date: on_date)
          on_date
        rescue ArgumentError, Core::BusinessDate::Errors::NotSet, Core::BusinessDate::Errors::InvalidPostingBusinessDate => e
          raise InvalidRequest, e.message
        end
        private_class_method :normalize_business_date

        def self.normalize_required_identifier(value, label)
          normalized = value.to_s.strip
          raise InvalidRequest, "#{label} is required" if normalized.blank?

          normalized
        end
        private_class_method :normalize_required_identifier

        def self.normalize_required_account_number(value)
          normalized = value.to_s.strip
          raise InvalidRequest, "account_number is required" if normalized.blank?

          normalized
        end
        private_class_method :normalize_required_account_number

        def self.normalize_amount(value)
          amount = Integer(value)
          raise InvalidRequest, "amount_minor_units must be positive" unless amount.positive?

          amount
        rescue ArgumentError, TypeError
          raise InvalidRequest, "amount_minor_units must be positive"
        end
        private_class_method :normalize_amount

        def self.normalize_currency(value)
          currency = value.to_s.strip.upcase
          raise InvalidRequest, "currency must be USD" unless currency == CURRENCY

          currency
        end
        private_class_method :normalize_currency

        def self.idempotency_key(file_id:, batch_id:, item_id:)
          "ach-credit-received:#{file_id}:#{batch_id}:#{item_id}"
        end
        private_class_method :idempotency_key

        def self.reference_id(file_id:, batch_id:, item_id:)
          "ach:#{file_id}:#{batch_id}:#{item_id}"
        end
        private_class_method :reference_id

        def self.existing_event(idempotency_key)
          Core::OperationalEvents::Models::OperationalEvent
            .includes(posting_batches: :journal_entries)
            .find_by(channel: CHANNEL, idempotency_key: idempotency_key)
        end
        private_class_method :existing_event

        def self.preview_row(item_attrs, account:)
          item_row(item_attrs, deposit_account_id: account.id, outcome: :posted, message: "preview: ACH credit would be posted")
        end
        private_class_method :preview_row

        def self.invalid_item_row(file_id:, batch_id:, item:, message:)
          values = item.respond_to?(:to_h) ? item.to_h.with_indifferent_access : {}
          item_row(
            {
              file_id: file_id,
              batch_id: batch_id,
              item_id: values[:item_id].to_s.strip,
              account_number: values[:account_number].to_s.strip,
              amount_minor_units: values[:amount_minor_units],
              currency: values[:currency].to_s.strip.upcase,
              reference_id: nil,
              idempotency_key: nil
            },
            outcome: :invalid_item,
            message: message
          )
        end
        private_class_method :invalid_item_row

        def self.item_row(attrs, deposit_account_id: nil, event: nil, outcome:, message:)
          posting_batch = event&.posting_batches&.order(:id)&.last
          journal_entry = posting_batch&.journal_entries&.order(:id)&.last

          {
            file_id: attrs.fetch(:file_id),
            batch_id: attrs.fetch(:batch_id),
            item_id: attrs.fetch(:item_id),
            account_number: attrs.fetch(:account_number),
            deposit_account_id: deposit_account_id,
            operational_event_id: event&.id,
            posting_batch_id: posting_batch&.id,
            journal_entry_id: journal_entry&.id,
            reference_id: attrs.fetch(:reference_id),
            idempotency_key: attrs.fetch(:idempotency_key),
            outcome: outcome,
            message: message
          }
        end
        private_class_method :item_row

        def self.outcome_message(outcome)
          {
            posted: "ACH credit posted",
            pending_posted: "pending ACH credit replay posted",
            already_posted: "ACH credit was already posted"
          }.fetch(outcome)
        end
        private_class_method :outcome_message
      end
    end
  end
end
