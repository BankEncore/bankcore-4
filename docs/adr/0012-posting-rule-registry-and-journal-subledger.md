# ADR-0012: Posting rule registry and journal subledger (`deposit_account_id`)

**Status:** Accepted  
**Date:** 2026-04-23  
**Decision Type:** Core posting architecture  
**Aligns with:** [ADR-0003](0003-posting-journal-architecture.md), [ADR-0010](0010-ledger-persistence-and-seeded-coa.md), [ADR-0002](0002-operational-event-model.md), [docs/operational_events/README.md](../operational_events/README.md)

---

## 1. Context

Slice 1 inlined GL mapping inside `PostEvent` for a single `event_type`. Phase 1 adds withdrawals, transfers, and reversals; a growing `case` on `event_type` is hard to test and review.

Per-account liability on GL **2110** cannot be inferred from aggregate GL rows alone; internal transfers require distinct subledger attribution on both legs.

---

## 2. Decision

1. **`Core::Posting::PostingRules::Registry`** maps `event_type` string → a small rule module that returns an ordered list of **`PostingLeg`** structs (`gl_account_number`, `side`, `amount_minor_units`, optional `deposit_account_id`).
2. **`Core::Posting::Commands::PostEvent`** owns batch + journal persistence only; it resolves legs via the registry, validates Σ debits = Σ credits, resolves `GlAccount` rows by `account_number` (seeded COA per ADR-0010 §3.2), and persists `journal_lines` including **`deposit_account_id`** where the leg is customer DDA liability (2110).
3. **Ownership:** `Core::Posting` owns the registry and rule modules under `app/domains/core/posting/posting_rules/`. Other domains must not insert `journal_lines` directly.

---

## 3. MVP rules registered

| `event_type` | Summary |
| ------------ | ------- |
| `deposit.accepted` | Dr 1110 / Cr 2110; Cr leg carries `deposit_account_id` = `source_account_id`. |
| `withdrawal.posted` | Dr 2110 (`deposit_account_id` = source) / Cr 1110. |
| `transfer.completed` | Dr 2110 (source) / Cr 2110 (destination). |
| `posting.reversal` | Mirror lines of the original journal (see [ADR-0003](0003-posting-journal-architecture.md) reversals); subledger ids copied per line. |
| `fee.assessed` | Dr **2110** (`deposit_account_id` = `source_account_id`) / Cr **4510** ([ADR-0019](0019-event-catalog-and-fee-events.md)). |
| `fee.waived` | Dr **4510** / Cr **2110** (`deposit_account_id` = `source_account_id`) ([ADR-0019](0019-event-catalog-and-fee-events.md)). |
| `teller.drawer.variance.posted` | Shortage: Dr **5190** / Cr **1110**; overage: Dr **1110** / Cr **5190**; magnitude `abs(amount_minor_units)`; signed amount on event ([ADR-0020](0020-teller-drawer-variance-gl-posting.md)). |
| `interest.accrued` | Dr **5100** / Cr **2510** (`deposit_account_id` = `source_account_id` on 2510 payable leg) ([ADR-0021](0021-interest-accrual-and-payout-slice.md)). |
| `interest.posted` | Dr **2510** / Cr **2110** (`deposit_account_id` = `source_account_id` on both legs) ([ADR-0021](0021-interest-accrual-and-payout-slice.md)). |

---

## 4. Consequences

- New financial `event_type` values require a registry entry, posting rule implementation, `RecordEvent` (or dedicated command) validation, idempotency fingerprint, tests, and `docs/operational_events/` spec alignment.
- **Available balance** for authorization uses ledger projection on **2110** lines filtered by `deposit_account_id` minus active **`holds`** ([ADR-0004](0004-account-balance-model.md)); implemented in `Accounts::Services::AvailableBalanceMinorUnits`.

---

## 5. References

- [docs/operational_events/deposit-accepted.md](../operational_events/deposit-accepted.md)
- [docs/operational_events/withdrawal-posted.md](../operational_events/withdrawal-posted.md)
- [docs/operational_events/transfer-completed.md](../operational_events/transfer-completed.md)
- [docs/operational_events/compensating-reversal.md](../operational_events/compensating-reversal.md)
- [docs/operational_events/interest-accrued.md](../operational_events/interest-accrued.md)
- [docs/operational_events/interest-posted.md](../operational_events/interest-posted.md)
