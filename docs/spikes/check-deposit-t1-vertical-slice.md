# Spike: T1 check deposit vertical slice

**Status:** **Implemented** in `EventCatalog`, `RecordEvent`, `PostingRules`, and teller **`AcceptCheckDeposit`** orchestration per [ADR-0040](../adr/0040-check-deposit-vertical-slice.md).

**Goal:** Branch-facing **check deposit** as the first **instrument** family: durable audit of items credited to a DDA with **availability / hold** discipline distinct from aggregate cash `deposit.accepted`.

**Capability taxonomy:** [303-bank-transaction-capability-taxonomy.md](../concepts/303-bank-transaction-capability-taxonomy.md).

---

## Problem statement

Today `deposit.accepted` models “cash or equivalent in” with immediate posting pattern ([deposit-accepted.md](../operational_events/deposit-accepted.md)). Checks need:

- **Item identity** (at least surrogate keys: serial, amount, perhaps MICR placeholders later).
- **Funds availability policy** — provisional ledger vs holds-only-first vs hybrid (policy ADR).
- **Often no teller drawer delta** at acceptance (contrast cash deposits under [ADR-0039](../adr/0039-teller-session-drawer-custody-projection.md)).

ADR-0040 now fixes the T1 direction:

- new financial event type: **`check.deposit.accepted`**
- posting at acceptance time
- debit **1160 Deposited Items Clearing** / credit **2110** DDA
- multi-item typed JSON payload on the event
- optional but supported **event-level** hold linkage only
- teller/session attribution allowed, but **no drawer projection** and **no expected-cash impact**

---

## Proposed directions (pick one in ADR)

### Option A — Single financial event

- One `event_type` **`check.deposit.accepted`** with `pending → posted`, posting rule debits **1160 Deposited Items Clearing** and credits **2110**, with availability driven by event-level hold rules.

### Option B — Split operational + financial

- Non-financial `check.deposit.received` (item custody / intake) plus financial `check.deposit.posted` when funds released — heavier; matches batch clearing mental model later.

### Option C — Extend payload on existing type

- Reuse `deposit.accepted` with `instrument_kind` / payload discriminant — minimal new types but risks overloading semantics and reversals.

**ADR outcome:** Option A chosen in [ADR-0040](../adr/0040-check-deposit-vertical-slice.md). Option B remains a future lifecycle-deepening alternative if clearing/returns later require a split intake/posting model.

---

## Integration touchpoints (implementation checklist)

Run **`rake spike:check_deposit_t1`** for the canonical list of Ruby paths.

Conceptual order:

1. **ADR** — availability, posting timing, reversal rules, drawer exclusion defaults.
2. **`Core::OperationalEvents::EventCatalog`** + **`docs/operational_events/*.md`** + README index (required together per drift tests).
3. **`RecordEvent`** — whitelist type; validations (account open, amounts, optional `teller_session_id` policy).
4. **`Core::Posting::PostingRules::Registry`** — balanced legs for **Dr 1160 / Cr 2110**; later slices may decide how on-us and transit items relieve the clearing balance. The same change set should wire the documented `1160:{business_date}:{operational_event_id}` subledger pattern and any required seeded/control-account support.
5. **`Accounts::Commands::PlaceHold`** — T1 uses **event-level** hold linkage only; item-specific hold linkage is deferred even when the payload contains multiple items.
6. **`Cash::Services::TellerEventProjector`** — exclude or conditional-include check deposit types so drawer custody stays accurate ([ADR-0039](../adr/0039-teller-session-drawer-custody-projection.md)).
7. **`Teller::Queries::ExpectedCashForSession`** — ensure check deposits do not inflate drawer expected cash.
8. **Reversal** — `RecordReversal` eligibility and deposit-linked hold guards mirror `deposit.accepted`.
9. **Branch / Teller controllers** — operator UX for items + totals + session context.
10. **Tests** — domain + integration; event catalog drift suite.

---

## Explicit non-goals (this spike)

- ACH/check clearing networks, returns workflow, image capture.
- Official checks / check cashing (T2).
- Full close-package taxonomy (T4).
- Item-specific hold linkage, item-by-item release, or per-item reversal semantics.
- Differentiated posting treatment between on-us and transit deposited checks; T1 uses generic clearing account **1160**, while **1140 CIPC** remains reserved for external/transit collection semantics.

---

## References

- [ADR-0013](../adr/0013-holds-available-and-servicing-events.md) — holds vs availability.
- [ADR-0019](../adr/0019-event-catalog-and-fee-events.md) — catalog discipline.
- [ADR-0040](../adr/0040-check-deposit-vertical-slice.md) — accepted T1 decision boundary.
- Roadmap Phase 5 instruments: [roadmap-branch-operations.md](../roadmap-branch-operations.md).
