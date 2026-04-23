# ADR-0016: Trial balance query and EOD readiness (MVP)

**Status:** Accepted  
**Date:** 2026-04-24  
**Aligns with:** [roadmap.md](../roadmap.md) Phase 1F, [module catalog](../architecture/bankcore-module-catalog.md) §6.3–6.4, [ADR-0010](0010-ledger-persistence-and-seeded-coa.md), [ADR-0003](0003-posting-journal-architecture.md)

---

## 1. Context

Phase 1 needs **read-only** visibility into whether **GL activity for a business date nets to balanced totals** and whether **branch-style preconditions** (no open teller sessions, no stuck pending events) are satisfied before treating the day as operationally closed. Formal **day close** / posting locks are deferred ([roadmap.md](../roadmap.md) Phase 2).

---

## 2. Decisions

### 2.1 Trial balance (Core::Ledger)

- **Owner:** `Core::Ledger::Queries::TrialBalanceForBusinessDate` returns **activity-only** rows: one row per `gl_accounts` row that has non-zero **debit** or **credit** sums of `journal_lines` for **`journal_entries.business_date = :business_date`**.
- Columns exposed per row: `gl_account_id`, `account_number`, `account_name`, `account_type`, `debit_minor_units`, `credit_minor_units` (side splits from posted lines only).
- **`JournalBalanceCheckForBusinessDate`** sums all debits and all credits for lines on entries with that **business_date** and sets **`balanced`** when totals are equal. This is a **defensive** cross-check (each journal is already balanced at post time per `PostEvent`).

### 2.2 EOD readiness (Teller orchestration)

- **Owner:** `Teller::Queries::EodReadiness` composes ledger checks, **`teller_sessions`** inventory, and **`operational_events`** pending count for the same **business_date**. `Core::BusinessDate` does **not** depend on `Teller` (dependency direction).
- **`open_teller_sessions_count`:** sessions in **`open`** or **`pending_supervisor`** (anything not **`closed`** that still blocks “all drawers settled”).
- **`all_sessions_closed`:** `open_teller_sessions_count.zero?`.
- **`pending_operational_events_count`:** `operational_events` with **`status = pending`** and **`business_date`** match.
- **`eod_ready`:** `journal_totals_balanced && all_sessions_closed && pending_operational_events_count.zero?`.
- **Institution-wide MVP:** there is **no `branch_id`** on journals or sessions; counts apply to the whole database. Multi-branch scoping is a future ADR.

### 2.3 HTTP (teller workspace)

- **`GET /teller/reports/trial_balance`** and **`GET /teller/reports/eod_readiness`** require **`X-Operator-Id`** ([ADR-0015](0015-teller-workspace-authentication.md)). **No supervisor-only gate** in MVP (same as plan default); tighten later if product requires.
- Query param **`business_date`** (ISO **YYYY-MM-DD**). **Omitted** → use **`Core::BusinessDate::Services::CurrentBusinessDate`**.
- **Validation:** malformed date → **422** `invalid_request`. **`business_date` strictly after** current business date → **422** (no future-dated reporting). Dates **on or before** current business date are allowed (historical trial balance).

---

## 3. Consequences

- Reporting remains **read-only**; no new write paths to `journal_entries` / `journal_lines`.
- An index on **`journal_entries.business_date`** supports aggregates at modest volume.

---

## 4. References

- Implementation: `Core::Ledger::Queries::TrialBalanceForBusinessDate`, `JournalBalanceCheckForBusinessDate`, `Teller::Queries::EodReadiness`, `Teller::ReportsController`.
