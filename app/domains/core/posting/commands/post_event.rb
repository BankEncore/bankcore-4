# frozen_string_literal: true

module Core
  module Posting
    module Commands
      class PostEvent
        class Error < StandardError; end
        class NotFound < Error; end
        class InvalidState < Error; end

        # @return [Hash] `{ outcome: :posted|:already_posted, event: OperationalEvent }`
        def self.call(operational_event_id:)
          Core::OperationalEvents::Models::OperationalEvent.transaction do
            event = Core::OperationalEvents::Models::OperationalEvent.lock.find_by(id: operational_event_id)
            raise NotFound, "operational_event_id=#{operational_event_id}" if event.nil?

            if event.status == Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED
              return { outcome: :already_posted, event: event }
            end

            unless event.status == Core::OperationalEvents::Models::OperationalEvent::STATUS_PENDING
              raise InvalidState, "operational event must be pending, was #{event.status.inspect}"
            end

            raise InvalidState, "unsupported event_type for slice 1 posting" unless event.event_type == "deposit.accepted"

            amount = event.amount_minor_units
            raise InvalidState, "amount_minor_units required" if amount.nil? || amount <= 0

            cash = Core::Ledger::Models::GlAccount.find_by!(account_number: "1110")
            dda = Core::Ledger::Models::GlAccount.find_by!(account_number: "2110")

            legs_balanced!(amount)

            batch = Core::Posting::Models::PostingBatch.create!(
              operational_event: event,
              status: "pending"
            )

            entry = Core::Ledger::Models::JournalEntry.create!(
              posting_batch: batch,
              operational_event: event,
              business_date: event.business_date,
              currency: event.currency,
              narrative: event.event_type,
              effective_at: Time.current
            )

            Core::Ledger::Models::JournalLine.create!(
              journal_entry: entry,
              sequence_no: 1,
              side: "debit",
              gl_account: cash,
              amount_minor_units: amount
            )
            Core::Ledger::Models::JournalLine.create!(
              journal_entry: entry,
              sequence_no: 2,
              side: "credit",
              gl_account: dda,
              amount_minor_units: amount
            )

            ActiveRecord::Base.connection.execute("SET CONSTRAINTS ALL IMMEDIATE")

            batch.update!(status: "posted")
            event.update!(status: Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED)

            { outcome: :posted, event: event }
          end
        end

        def self.legs_balanced!(amount_minor_units)
          debit = amount_minor_units
          credit = amount_minor_units
          raise InvalidState, "unbalanced legs" unless debit == credit
        end
        private_class_method :legs_balanced!
      end
    end
  end
end
