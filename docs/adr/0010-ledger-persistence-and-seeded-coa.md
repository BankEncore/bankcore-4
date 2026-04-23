# ADR-0010: Ledger persistence, balancing, immutability, and seeded COA (MVP)

**Status:** Accepted  
**Date:** 2026-04-22  
**Decision Type:** Core financial persistence  
**Aligns with:** [ADR-0003](0003-posting-journal-architecture.md), [ADR-0008](0008-money-currency-rounding-policy.md), [ADR-0002](0002-operational-event-model.md), [docs/architecture/bankcore-module-catalog.md](../architecture/bankcore-module-catalog.md) §6.3–6.4, §10

---

## 1. Context

BankCORE needs durable **GL and journal** structures before posting commands can persist balanced entries. This ADR fixes the **relational shape** for the first vertical slice while documenting **MVP exceptions** to broader ADR wording where the slice intentionally simplifies.

---

## 2. Table ownership

| Table                 | Owning module                 |
| --------------------- | ----------------------------- |
| `gl_accounts`         | `Core::Ledger`                |
| `journal_entries`     | `Core::Ledger`                |
| `journal_lines`       | `Core::Ledger`                |
| `operational_events`  | `Core::OperationalEvents`     |
| `posting_batches`     | `Core::Posting`               |

Rails models live under `app/domains/core/ledger/models/`, `app/domains/core/operational_events/models/`, `app/domains/core/posting/models/` per module catalog.

---

## 3. MVP exceptions (explicit)

### 3.1 ADR-0003 §6.1 posting batch vs journal

Long term, `journal_entries` link to **`posting_batch_id`** (and event context). For MVP we **also** store **`operational_event_id`** on `journal_entries` (denormalized) for simple queries until read models mature.

### 3.2 ADR-0003 §7.2 hardcoded GL

The posting engine **must not** hardcode GL accounts at steady state. **MVP:** seed `gl_accounts` with stable **`account_number`** values and resolve posting rules by those numbers (or IDs) until `GlMappingResolver` and Products configuration exist. Document each hardcoded mapping in posting code comments referencing this ADR.

---

## 4. `gl_accounts`

| Column             | Type     | Constraints / notes |
| ------------------ | -------- | --------------------- |
| `id`               | bigint   | PK                    |
| `account_number`   | string   | NOT NULL, UNIQUE      |
| `account_type`     | string   | NOT NULL — app enum: `asset`, `liability`, `equity`, `revenue`, `expense` (no DB CHECK in MVP; see ADR-0009-style enums) |
| `natural_balance`  | string   | NOT NULL — `debit` \| `credit` (normal balance) |
| `account_name`     | string   | NOT NULL              |
| `currency`         | string   | NOT NULL, default `USD` (ISO 4217; single-currency MVP per ADR-0008 §3.2) |
| `active`           | boolean  | NOT NULL, default true |
| `created_at` / `updated_at` | datetime | |

**Rules:** Do not repurpose **`account_number`** for a different economic meaning once lines reference the row; retire via **`active: false`** (or add effective dating later).

---

## 5. `operational_events` (minimal slice columns)

Full lifecycle, idempotency scope, status vocabulary, column roadmap, and composition rules are specified in [ADR-0002](0002-operational-event-model.md) (**§3.2**, **§3.3**, **§7.3**, **§8**). This section lists **MVP persisted columns** for the ledger slice.

| Column             | Type     | Notes |
| ------------------ | -------- | ----- |
| `id`               | bigint   | PK    |
| `event_type`       | string   | NOT NULL |
| `status`           | string   | NOT NULL — app enum: `pending`, `posted` (cross-layer semantics: ADR-0002 §3.2; not `reversed` on the same row under ADR-0002 §6.1) |
| `business_date`    | date     | NOT NULL |
| `channel`          | string   | NOT NULL — submission path for **scoped idempotency** (e.g. `teller`, `api`, `batch`, `system`; ADR-0002 §7.3). |
| `idempotency_key`  | string   | NOT NULL — unique **together with** `channel` (`UNIQUE (channel, idempotency_key)`); stored exactly as submitted (ADR-0002 §7.3). |
| `amount_minor_units` | bigint | nullable (financial events) |
| `currency`         | string   | nullable |
| `source_account_id` | bigint  | nullable, FK → **`deposit_accounts`** — populated for slice-1 **`deposit.accepted`** (and future account-sourced events); see [ADR-0011](0011-accounts-deposit-vertical-slice-mvp.md) §2.5. |
| `destination_account_id` | bigint | nullable, FK → **`deposit_accounts`** — **`transfer.completed`**. |
| `reversal_of_event_id` / `reversed_by_event_id` | bigint | nullable, self-FK — compensating **`posting.reversal`** linkage (ADR-0002 §6). |
| `teller_session_id` | bigint | nullable, FK → **`teller_sessions`**. |
| `reference_id` | string | nullable — control events, external correlation. |
| `actor_id` | bigint | nullable — operator stub until identity tables land. |
| `created_at` / `updated_at` | datetime | |

---

## 6. `posting_batches`

| Column                 | Type   | Notes |
| ---------------------- | ------ | ----- |
| `id`                   | bigint | PK    |
| `operational_event_id` | bigint | NOT NULL, FK → `operational_events` |
| `status`               | string | NOT NULL — app enum: `pending`, `posted`, `failed` (MVP) |
| `created_at` / `updated_at` | datetime | |

One batch groups all posting legs for a single operational event (ADR-0003 §4.1).

---

## 7. `journal_entries`

Persist **only balanced** entries in the same transaction as their lines (ADR-0003 §5.2). **`status`** column uses a single persisted value **`posted`** for rows created by the ledger in MVP (no `pending` journal row); future workflows may add staging states.

| Column                      | Type       | Notes |
| --------------------------- | ---------- | ----- |
| `id`                        | bigint     | PK    |
| `posting_batch_id`          | bigint     | NOT NULL, FK → `posting_batches` |
| `operational_event_id`      | bigint     | NOT NULL, FK → `operational_events` (denormalized) |
| `business_date`             | date       | NOT NULL |
| `currency`                  | string     | NOT NULL (must match lines’ economic currency; ADR-0008 §3.2) |
| `narrative`                 | string     | nullable |
| `effective_at`            | timestamptz | NOT NULL, default now() |
| `status`                    | string     | NOT NULL, default `posted` |
| `reverses_journal_entry_id` | bigint     | nullable, self-FK → `journal_entries` |
| `reversing_journal_entry_id`| bigint     | nullable, self-FK (set when this entry is reversed by a newer one) |
| `created_at` / `updated_at` | datetime   | |

**Void:** omitted in MVP; use **reversal** postings per ADR-0003 §8. **`voided_*` / actors** omitted until operator identity tables exist.

---

## 8. `journal_lines`

| Column                 | Type   | Notes |
| ---------------------- | ------ | ----- |
| `id`                   | bigint | PK    |
| `journal_entry_id`     | bigint | NOT NULL, FK → `journal_entries` |
| `sequence_no`          | integer| NOT NULL, UNIQUE per `journal_entry_id` |
| `side`                 | string | NOT NULL — `debit` \| `credit` |
| `gl_account_id`        | bigint | NOT NULL, FK → `gl_accounts` |
| `amount_minor_units`   | bigint | NOT NULL, **CHECK (amount_minor_units >= 0)** (ADR-0008 §5.1) |
| `narrative`            | string | nullable |
| `created_at` / `updated_at` | datetime | |
| `deposit_account_id` | bigint | nullable, FK → **`deposit_accounts`** — **subledger** for customer DDA liability on **2110** legs (ADR-0012); null for cash (1110) legs and legacy rows. |

---

## 9. Balancing enforcement

1. **Application:** `Core::Posting` / ledger services **must** validate Σ debits == Σ credits in minor units before commit (ADR-0003 §5.2).
2. **Database:** **DEFERRABLE INITIALLY DEFERRED** constraint trigger on `journal_lines` validates the parent `journal_entry_id` at **transaction commit** so multi-line inserts remain valid mid-transaction.

**Schema dumps:** The app uses **`config.active_record.schema_format = :sql`** so `db/structure.sql` (via `pg_dump`) includes triggers and functions. The Docker dev image installs `postgresql-client` for dumps. Do not rely on `db/schema.rb` for ledger DDL.

---

## 10. Immutability

- **`journal_lines`:** append-only — **no UPDATE or DELETE** enforced with a **BEFORE UPDATE OR DELETE** trigger that raises.
- **`journal_entries`:** no UPDATE or DELETE after insert **except** one narrow case: setting **`reversing_journal_entry_id`** on the **original** entry when a compensating reversal entry is persisted (ADR-0003 reversal linkage). A replacement trigger function allows **only** that column to change from NULL to the new entry’s id when all other business columns are unchanged (migration `AllowJournalEntryReversalLinkUpdate`).
- Enforcement is **DB-level** for defense in depth; domain code must still treat models as read-only after create.

---

## 11. Seeded COA (chart of accounts)

GL accounts are seeded from **[docs/concepts/100-chart-of-accounts.tsv](../concepts/100-chart-of-accounts.tsv)** via [lib/bank_core/seeds/gl_coa.rb](../../lib/bank_core/seeds/gl_coa.rb). TSV `Type` maps to persisted `account_type` / `natural_balance` as: Asset and Contra-Asset → `asset` / `debit`; Liability → `liability` / `credit`; Equity → `equity` / `credit`; Income → `revenue` / `credit`; Expense → `expense` / `debit`.

**First slice (teller cash deposit) posting pairs** (MVP hard-coded mapping): debit **`1110`** (Cash in Vaults), credit **`2110`** (Noninterest-Bearing Demand Deposits) for the event amount in minor units.

---

## 12. Related ADRs

* [ADR-0002](0002-operational-event-model.md)  
* [ADR-0003](0003-posting-journal-architecture.md)  
* [ADR-0008](0008-money-currency-rounding-policy.md)  
* [ADR-0011](0011-accounts-deposit-vertical-slice-mvp.md) — `deposit_accounts`, **`deposit_account_parties`**, and **`operational_events.source_account_id`** for slice-1 **`deposit.accepted`**

---

## 13. Summary

`Core::Ledger` owns **`gl_accounts`**, **`journal_entries`**, **`journal_lines`** with ADR-0008-friendly amounts, commit-time balance validation, and immutable posted rows. **`posting_batches`** and **`operational_events`** (including optional **`source_account_id`** for account-linked financial events) satisfy ADR-0003 linkage. MVP seeds the full chart from the TSV; the first cash deposit posting rule still hard-codes GL account numbers (`1110` / `2110`), which is an explicit temporary exception to ADR-0003 §7.2.
