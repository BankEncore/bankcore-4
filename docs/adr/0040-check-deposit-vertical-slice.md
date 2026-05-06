# ADR-0040: Check deposit vertical slice

**Status:** Accepted  
**Date:** 2026-05-03  
**Decision Type:** Teller transaction family / instrument intake / funds availability  
**Aligns with:** [ADR-0002](0002-operational-event-model.md), [ADR-0013](0013-holds-available-and-servicing-events.md), [ADR-0019](0019-event-catalog-and-fee-events.md), [ADR-0039](0039-teller-session-drawer-custody-projection.md), [302-teller-transaction-surface.md](../concepts/302-teller-transaction-surface.md), [303-bank-transaction-capability-taxonomy.md](../concepts/303-bank-transaction-capability-taxonomy.md)

---

## 1. Context

BankCORE's shipped teller/deposit path models cash deposit through `deposit.accepted`: teller or branch staff can record a deposit event, post it through `Core::Posting`, credit a demand deposit account, and project posted teller cash activity into expected drawer cash and Cash-domain drawer custody where applicable.

That model is intentionally cash-oriented. It does not yet cover the first instrument family: branch-facing check deposit. Checks differ from cash deposits in ways that matter to operational semantics:

- a single customer action may include multiple deposited items
- teller/session attribution matters for audit and support even when no drawer cash delta occurs
- funds availability may be constrained independently from ledger posting
- future slices may introduce clearing, returns, and automated availability policy without changing the core event boundary

BankCORE needs a narrow first slice that lets branch staff accept deposited checks into a DDA using the existing operational-event and posting kernel, while preserving a clean distinction from cash deposits.

This ADR covers only T1 check deposit intake. It does not implement check clearing, returns, image capture, official checks, check cashing, or a generalized negotiable-instrument lifecycle.

---

## 2. Decision Drivers

- Preserve the current financial write path: durable operational event first, posting through `Core::Posting`, immutable reversal via new events.
- Keep `deposit.accepted` semantically cash-only for the current shipped slice.
- Support multi-item branch/teller deposits without forcing a global `operational_event_lines` model.
- Reuse the existing hold and available-balance model where possible.
- Keep teller accountability visible through `actor_id`, `channel`, `operating_unit_id`, and `teller_session_id` without incorrectly changing drawer cash.
- Leave room for later clearing, returns, and automated availability policy without requiring a breaking event-model rewrite.

---

## 3. Considered Options

| Option | Pros | Cons |
| :--- | :--- | :--- |
| **A. New single financial event: `check.deposit.accepted`** | Fits current `pending -> posted` kernel; keeps cash and check semantics distinct; supports statements, balances, and reversal machinery immediately; narrowest vertical slice. | Treats accepted check deposit as ledger-crediting before future clearing/return lifecycle exists; needs typed item payload and hold-linking decisions now. |
| **B. Split operational + financial lifecycle: `check.deposit.received` then `check.deposit.posted`** | Closer to future clearing mental model; separates intake from financial availability. | Heavier T1 slice; introduces more lifecycle and queue semantics before BankCORE has clearing/settlement depth; larger blast radius for close and support reads. |
| **C. Reuse `deposit.accepted` with an instrument discriminator** | Lowest immediate vocabulary expansion. | Overloads shipped cash semantics; weakens event-catalog clarity; complicates teller cash projection, reversal policy, and future instrument-specific rules. |
| **D. Rename `deposit.accepted` to `cash.deposit.accepted` as part of T1** | Creates a cleaner long-term naming scheme. | Broad churn across shipped code, docs, tests, and ADRs without improving T1 behavior directly; mixes catalog migration into an instrument slice. |

---

## 4. Decision Outcome

**Chosen option: A. Add new single financial event `check.deposit.accepted`.**

BankCORE will implement T1 check deposit as a new financial operational event type, `check.deposit.accepted`, with the same persisted lifecycle shape as other posted financial events: `pending` on record, `posted` after successful `Core::Posting::Commands::PostEvent`.

`deposit.accepted` remains the shipped cash-deposit event in this slice. T1 does not rename or migrate the existing event vocabulary.

### 4.1 Event semantics

`check.deposit.accepted` means the institution accepted one or more deposited check items for credit to a specific demand deposit account.

The event:

- must reference an open deposit account
- must carry a positive total `amount_minor_units`
- must include a typed JSON payload describing one or more deposited items
- must satisfy `amount_minor_units == sum(items[].amount_minor_units)`; record validation rejects any request whose aggregate total and item totals differ
- may include `teller_session_id` when initiated through teller/branch teller execution surfaces
- does not imply cash drawer increase merely because a teller handled it

### 4.2 Lifecycle and posting timing

T1 uses a single financial event lifecycle:

1. `RecordEvent` creates `check.deposit.accepted` in `pending`
2. `PostEvent` applies balanced journal entries and marks the event `posted`

Posting occurs at acceptance time in this slice, not only after a future clearing/release step.

This keeps the check-deposit slice compatible with existing account balance, statement, event-history, and reversal machinery while leaving returns and settlement depth for later ADRs.

### 4.3 Availability model

T1 uses the existing Accounts-owned hold model to constrain funds availability.

- Ledger credit and available funds are intentionally separate concerns.
- `check.deposit.accepted` may be posted with no hold, or with one or more linked holds that reduce available balance.
- Hold placement is optional but supported in T1.
- T1 supports event-level hold linkage only: linked holds attach to the deposited operational event as a whole, not to individual items inside `items[]`.
- The sum of active linked holds may not exceed the total event `amount_minor_units`.
- T1 does not support item-specific hold linkage, item-by-item release, or per-item reversal semantics.
- T1 does not implement a full Reg CC schedule, collected-funds engine, automatic release timing, or product-driven exception-hold automation.

This means T1 supports manual or policy-invoked hold discipline without introducing a second provisional-ledger model.

### 4.4 Item representation

T1 uses a typed JSON payload on the operational event, not first-class child rows.

The payload must support multiple deposited items in one customer action. The minimum T1 payload shape should include:

- `items[]`
- per item:
  - `amount_minor_units`
  - structured check identity: `routing_number`, `account_number`, and `check_serial_number`
  - legacy compatibility identity: `item_reference` or `serial_number`

Optional placeholders such as on-us/transit metadata may be added if needed for the first slice, but T1 does not require full MICR parsing, image capture, or clearing identifiers.

This follows ADR-0002's guidance that instrument-heavy or mixed deposits may use a typed payload or child rows per family, without forcing a global line-item architecture.

**2026-05-06 amendment:** Branch check-deposit intake now prompts for and transmits structured check identity (`routing_number`, `account_number`, `check_serial_number`) per item. The operational-event validator continues accepting the original `item_reference` / `serial_number` item shape for JSON client compatibility, but new Branch-originated check deposits should use the structured shape.

### 4.5 Posting and GL treatment

T1 posts accepted check deposits as non-cash deposited items, not as teller cash.

At posting time:

- debit GL `1160` Deposited Items Clearing
- credit DDA liability `2110` with deposit-account attribution

T1 does not differentiate posting treatment between on-us and transit checks.

Therefore:

- item metadata may capture a classification such as `on_us`, `transit`, or `unknown`
- that classification does not change the posting rule in T1
- T1 does not debit the maker/source account for on-us items
- T1 does not debit cash `1110`

This ADR intentionally chooses one generic clearing asset posture for the first slice so check deposit intake can ship without requiring internal presentment, maker-account linkage, or differentiated settlement paths.

GL `1160` is the placeholder deposited-items clearing asset for this slice. It should be described as a generic deposited-items clearing account rather than an external-only transit account.
GL `1140` Cash Items in Process of Collection remains available for external/transit collection semantics outside this narrow T1 posting decision.

### 4.6 Teller/session attribution vs drawer impact

`check.deposit.accepted` may carry `teller_session_id` for teller accountability, support traceability, and close/read-model attribution.

In T1, `teller_session_id` on check deposits is an execution-trace field, not a cash-custody projection trigger.

Therefore:

- posted `check.deposit.accepted` does **not** change expected cash for the teller session
- posted `check.deposit.accepted` does **not** create Cash-domain teller-event drawer projections under ADR-0039
- teller/session attribution remains queryable for support, exception review, and future close-package classification

### 4.7 Reversal policy

T1 allows reversal through existing `posting.reversal` mechanics when the event is otherwise eligible for reversal.

T1 keeps the current simple hold invariant:

- reversal is rejected while any active linked hold remains in effect for the deposited event

T1 does not yet distinguish automatic/system-generated availability holds from manual operator holds for reversal behavior. Any future policy that auto-releases system-generated holds while preserving manual holds requires a separate ADR or amendment because it changes hold taxonomy, reversal sequencing, and servicing audit semantics.

### 4.8 Channel posture

T1 is primarily a branch/teller-executed slice.

The event type may be permitted in teller-oriented execution paths with the same actor/scope rules as other staff-originated financial events:

- `actor_id` from staff/operator identity
- `operating_unit_id` from resolved scope
- `channel` from the producing surface

If later APIs or batch paths use `check.deposit.accepted`, they must obey the same event semantics and not introduce alternate posting or availability rules.

---

## 5. Consequences

### Positive

- BankCORE gains its first instrument-specific teller transaction family without overloading the cash deposit vocabulary.
- The slice reuses the existing operational-event, posting, statement-history, and hold infrastructure.
- Teller/session accountability is preserved without corrupting drawer cash or Cash custody semantics.
- Multi-item deposit support exists from the start at the payload level.

### Negative

- Posting at acceptance time means T1 intentionally stops short of full clearing and return realism.
- Typed JSON payloads are lighter than child rows but put more validation pressure on event-family-specific code.
- Reversal remains conservative because any active event-level linked hold blocks reversal.

### Neutral

- A later ADR may still normalize instrument ownership under a dedicated `Instruments` domain or another owner.
- A later ADR may still rename event families if BankCORE adopts a stricter `cash.*` / `check.*` vocabulary pattern.

---

## 6. Explicit Deferrals

T1 does **not** add:

- check clearing or settlement workflows
- check return / chargeback flows
- image capture or document retention
- official checks, drafts, or check cashing
- full close-package classification changes beyond carrying the new event and hold evidence
- automatic Reg CC scheduling or collected-funds release
- special reversal behavior that auto-releases system-generated holds
- first-class item child tables or a generalized `operational_event_lines` architecture

---

## 7. Implementation Notes

The first implementation should update these areas together:

- `Core::OperationalEvents::EventCatalog`
- `RecordEvent` allowlist and validation
- `PostingRules::Registry`
- operational-event documentation for `check.deposit.accepted`
- hold-linking behavior for optional availability holds
- `Cash::Services::TellerEventProjector` exclusion for check deposits
- `Teller::Queries::ExpectedCashForSession` confirmation that check deposits do not affect expected cash
- branch/teller input surfaces and integration tests

The canonical implementation checklist remains the T1 spike artifact:
[check-deposit-t1-vertical-slice.md](../spikes/check-deposit-t1-vertical-slice.md)

---

## 8. References

- [ADR-0002](0002-operational-event-model.md)
- [ADR-0013](0013-holds-available-and-servicing-events.md)
- [ADR-0019](0019-event-catalog-and-fee-events.md)
- [ADR-0039](0039-teller-session-drawer-custody-projection.md)
- [deposit.accepted](../operational_events/deposit-accepted.md)
- [302-teller-transaction-surface.md](../concepts/302-teller-transaction-surface.md)
- [303-bank-transaction-capability-taxonomy.md](../concepts/303-bank-transaction-capability-taxonomy.md)
