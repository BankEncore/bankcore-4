# frozen_string_literal: true

# Install ledger triggers in a dedicated migration so DDL is not skipped when batched
# with earlier steps (see docs/adr/0010-ledger-persistence-and-seeded-coa.md).
class InstallLedgerTriggers < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION ledger_validate_journal_entry_balanced() RETURNS trigger
        LANGUAGE plpgsql AS $$
      DECLARE
        jid bigint;
        sum_debits bigint;
        sum_credits bigint;
      BEGIN
        IF TG_OP = 'DELETE' THEN
          jid := OLD.journal_entry_id;
        ELSE
          jid := NEW.journal_entry_id;
        END IF;

        SELECT
          COALESCE(SUM(amount_minor_units) FILTER (WHERE side = 'debit'), 0),
          COALESCE(SUM(amount_minor_units) FILTER (WHERE side = 'credit'), 0)
        INTO sum_debits, sum_credits
        FROM journal_lines
        WHERE journal_entry_id = jid;

        IF sum_debits != sum_credits THEN
          RAISE EXCEPTION 'Journal entry % is not balanced (debits % vs credits %)',
            jid, sum_debits, sum_credits;
        END IF;

        RETURN COALESCE(NEW, OLD);
      END;
      $$;

      CREATE CONSTRAINT TRIGGER journal_lines_balance_check
      AFTER INSERT OR UPDATE OR DELETE ON journal_lines
      DEFERRABLE INITIALLY DEFERRED
      FOR EACH ROW
      EXECUTE FUNCTION ledger_validate_journal_entry_balanced();

      CREATE OR REPLACE FUNCTION ledger_journal_lines_reject_mutations() RETURNS trigger
        LANGUAGE plpgsql AS $$
      BEGIN
        IF TG_OP = 'UPDATE' OR TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'journal_lines are append-only (immutable)';
        END IF;
        RETURN NEW;
      END;
      $$;

      CREATE TRIGGER journal_lines_immutability_check
      BEFORE UPDATE OR DELETE ON journal_lines
      FOR EACH ROW
      EXECUTE FUNCTION ledger_journal_lines_reject_mutations();

      CREATE OR REPLACE FUNCTION ledger_journal_entries_reject_mutations() RETURNS trigger
        LANGUAGE plpgsql AS $$
      BEGIN
        IF TG_OP = 'UPDATE' OR TG_OP = 'DELETE' THEN
          RAISE EXCEPTION 'journal_entries are append-only (immutable)';
        END IF;
        RETURN NEW;
      END;
      $$;

      CREATE TRIGGER journal_entries_immutability_check
      BEFORE UPDATE OR DELETE ON journal_entries
      FOR EACH ROW
      EXECUTE FUNCTION ledger_journal_entries_reject_mutations();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS journal_entries_immutability_check ON journal_entries;
      DROP FUNCTION IF EXISTS ledger_journal_entries_reject_mutations();

      DROP TRIGGER IF EXISTS journal_lines_immutability_check ON journal_lines;
      DROP FUNCTION IF EXISTS ledger_journal_lines_reject_mutations();

      DROP TRIGGER IF EXISTS journal_lines_balance_check ON journal_lines;
      DROP FUNCTION IF EXISTS ledger_validate_journal_entry_balanced();
    SQL
  end
end
