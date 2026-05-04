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
            # Balance trigger is deferrable; defer until both lines exist (same pattern as prior implicit deferral).
            ActiveRecord::Base.connection.execute("SET CONSTRAINTS ALL DEFERRED")

            event = Core::OperationalEvents::Models::OperationalEvent.lock.find_by(id: operational_event_id)
            raise NotFound, "operational_event_id=#{operational_event_id}" if event.nil?

            if event.status == Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED
              Cash::Services::TellerEventProjector.call(operational_event_id: event.id)
              return { outcome: :already_posted, event: event }
            end

            unless event.status == Core::OperationalEvents::Models::OperationalEvent::STATUS_PENDING
              raise InvalidState, "operational event must be pending, was #{event.status.inspect}"
            end

            legs = PostingRules::Registry.legs_for(event)
            validate_balanced_legs!(legs)

            reverses_journal_entry_id = nil
            if event.event_type == "posting.reversal"
              orig = event.reversal_of_event
              raise InvalidState, "reversal_of_event required" if orig.nil?

              reverses_journal_entry_id = orig.journal_entries.order(:id).sole.id
            end

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
              effective_at: Time.current,
              reverses_journal_entry_id: reverses_journal_entry_id
            )

            legs.each do |leg|
              gl = Core::Ledger::Models::GlAccount.find_by!(account_number: leg.gl_account_number)
              Core::Ledger::Models::JournalLine.create!(
                journal_entry: entry,
                sequence_no: leg.sequence_no,
                side: leg.side,
                gl_account: gl,
                amount_minor_units: leg.amount_minor_units,
                deposit_account_id: leg.deposit_account_id
              )
            end

            Accounts::Services::DepositBalanceProjector.apply_journal_entry!(journal_entry: entry)

            ActiveRecord::Base.connection.execute("SET CONSTRAINTS ALL IMMEDIATE")

            batch.update!(status: "posted")
            event.update!(status: Core::OperationalEvents::Models::OperationalEvent::STATUS_POSTED)

            Cash::Services::TellerEventProjector.call(operational_event_id: event.id)
            link_reversal_journal!(event, entry) if event.event_type == "posting.reversal"

            { outcome: :posted, event: event }
          end
        end

        def self.validate_balanced_legs!(legs)
          deb = legs.sum { |l| l.side == "debit" ? l.amount_minor_units : 0 }
          cre = legs.sum { |l| l.side == "credit" ? l.amount_minor_units : 0 }
          raise InvalidState, "unbalanced legs" unless deb == cre
        end
        private_class_method :validate_balanced_legs!

        def self.link_reversal_journal!(reversal_event, reversal_entry)
          original = reversal_event.reversal_of_event
          return if original.nil?

          original_entry = original.journal_entries.order(:id).sole
          original_entry.update_columns(
            reversing_journal_entry_id: reversal_entry.id,
            updated_at: Time.current
          )
          original.update_columns(
            reversed_by_event_id: reversal_event.id,
            updated_at: Time.current
          )
        end
        private_class_method :link_reversal_journal!
      end
    end
  end
end
