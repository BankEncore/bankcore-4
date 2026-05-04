# Spike: T1 check deposit vertical slice

**Status:** Spike only — **not implemented** in `EventCatalog`, `RecordEvent`, or `PostingRules` yet.

**Goal:** Branch-facing **check deposit** as the first **instrument** family: durable audit of items credited to a DDA with **availability / hold** discipline distinct from aggregate cash `deposit.accepted`.

**Capability taxonomy:** [303-bank-transaction-capability-taxonomy.md](../concepts/303-bank-transaction-capability-taxonomy.md).

---

## Problem statement

Today `deposit.accepted` models “cash or equivalent in” with immediate posting pattern ([deposit-accepted.md](../operational_events/deposit-accepted.md)). Checks need:

- **Item identity** (at least surrogate keys: serial, amount, perhaps MICR placeholders later).
- **Funds availability policy** — provisional ledger vs holds-only-first vs hybrid (policy ADR).
- **Often no teller drawer delta** at acceptance (contrast cash deposits under [ADR-0039](../adr/0039-teller-session-drawer-custody-projection.md)).

---

## Proposed directions (pick one in ADR)

### Option A — Single financial event

- One `event_type` e.g. `check.deposit.accepted` with `pending → posted`, posting rule credits **2110** with availability driven by hold rules or subledger metadata.

### Option B — Split operational + financial

- Non-financial `check.deposit.received` (item custody / intake) plus financial `check.deposit.posted` when funds released — heavier; matches batch clearing mental model later.

### Option C — Extend payload on existing type

- Reuse `deposit.accepted` with `instrument_kind` / payload discriminant — minimal new types but risks overloading semantics and reversals.

**Recommendation for ADR workshop:** Option A or B; avoid C unless payload versioning is tightly controlled.

---

## Integration touchpoints (implementation checklist)

Run **`rake spike:check_deposit_t1`** for the canonical list of Ruby paths.

Conceptual order:

1. **ADR** — availability, posting timing, reversal rules, drawer exclusion defaults.
2. **`Core::OperationalEvents::EventCatalog`** + **`docs/operational_events/*.md`** + README index (required together per drift tests).
3. **`RecordEvent`** — whitelist type; validations (account open, amounts, optional `teller_session_id` policy).
4. **`Core::Posting::PostingRules::Registry`** — balanced legs; clarify interaction with **1120 / suspense** if checks settle separately later.
5. **`Accounts::Commands::PlaceHold`** — extend or add **item hold** pattern if `placed_for_operational_event_id` linkage is insufficient for multi-item deposits.
6. **`Cash::Services::TellerEventProjector`** — exclude or conditional-include check deposit types so drawer custody stays accurate ([ADR-0039](../adr/0039-teller-session-drawer-custody-projection.md)).
7. **`Teller::Queries::ExpectedCashForSession`** — ensure check deposits do not inflate drawer expected unless product explicitly treats “cash in envelope” separately.
8. **Reversal** — `RecordReversal` eligibility and deposit-linked hold guards mirror `deposit.accepted`.
9. **Branch / Teller controllers** — operator UX for items + totals + session context.
10. **Tests** — domain + integration; event catalog drift suite.

---

## Explicit non-goals (this spike)

- ACH/check clearing networks, returns workflow, image capture.
- Official checks / check cashing (T2).
- Full close-package taxonomy (T4).

---

## References

- [ADR-0013](../adr/0013-holds-available-and-servicing-events.md) — holds vs availability.
- [ADR-0019](../adr/0019-event-catalog-and-fee-events.md) — catalog discipline.
- Roadmap Phase 5 instruments: [roadmap-branch-operations.md](../roadmap-branch-operations.md).
