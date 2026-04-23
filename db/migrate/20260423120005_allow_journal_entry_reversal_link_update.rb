# frozen_string_literal: true

# Allow a single UPDATE on journal_entries: set reversing_journal_entry_id on the original entry
# after the compensating entry is inserted (ADR-0010 §7). All other mutations remain forbidden.
class AllowJournalEntryReversalLinkUpdate < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION ledger_journal_entries_reject_mutations() RETURNS trigger
        LANGUAGE plpgsql AS $$
      BEGIN
        IF TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'journal_entries are append-only (immutable)';
        END IF;
        IF TG_OP = 'UPDATE' THEN
          IF OLD.reversing_journal_entry_id IS NULL
             AND NEW.reversing_journal_entry_id IS NOT NULL
             AND OLD.id = NEW.id
             AND OLD.posting_batch_id IS NOT DISTINCT FROM NEW.posting_batch_id
             AND OLD.operational_event_id IS NOT DISTINCT FROM NEW.operational_event_id
             AND OLD.business_date IS NOT DISTINCT FROM NEW.business_date
             AND OLD.currency IS NOT DISTINCT FROM NEW.currency
             AND OLD.narrative IS NOT DISTINCT FROM NEW.narrative
             AND OLD.effective_at IS NOT DISTINCT FROM NEW.effective_at
             AND OLD.status IS NOT DISTINCT FROM NEW.status
             AND OLD.reverses_journal_entry_id IS NOT DISTINCT FROM NEW.reverses_journal_entry_id
             AND OLD.created_at IS NOT DISTINCT FROM NEW.created_at
          THEN
            RETURN NEW;
          END IF;
          RAISE EXCEPTION 'journal_entries are append-only (immutable)';
        END IF;
        RETURN NEW;
      END;
      $$;
    SQL
  end

  def down
    execute <<~SQL
      CREATE OR REPLACE FUNCTION ledger_journal_entries_reject_mutations() RETURNS trigger
        LANGUAGE plpgsql AS $$
      BEGIN
        IF TG_OP = 'UPDATE' OR TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'journal_entries are append-only (immutable)';
        END IF;
        RETURN NEW;
      END;
      $$;
    SQL
  end
end
