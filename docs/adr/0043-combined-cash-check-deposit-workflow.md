# ADR-0043: Combined cash and check deposit workflow

**Status:** Accepted  
**Date:** 2026-05-06  
**Decision Type:** Teller workflow orchestration / operational-event grouping  
**Aligns with:** [ADR-0002](0002-operational-event-model.md), [ADR-0013](0013-holds-available-and-servicing-events.md), [ADR-0039](0039-teller-session-drawer-custody-projection.md), [ADR-0040](0040-check-deposit-vertical-slice.md), [302-teller-transaction-surface.md](../concepts/302-teller-transaction-surface.md)

---

## 1. Context

Branch tellers need to accept a single customer deposit ticket that can include cash, one or more checks, or both. BankCORE already has separate durable event families for those instruments:

- `deposit.accepted` for teller cash deposits, including drawer custody projection where an open teller session is required.
- `check.deposit.accepted` for accepted check items, including structured item payloads, Dr `1160` / Cr `2110` posting, optional event-level holds, and no drawer cash delta.

A combined teller workflow must preserve those instrument-specific semantics while giving branch staff one operational action.

---

## 2. Decision Drivers

- Preserve existing posting rules and ledger invariants.
- Keep teller cash drawer custody tied only to actual cash.
- Keep accepted check item metadata and availability holds attached to the check event.
- Provide atomic operator behavior: either the requested cash/check portions all complete, or none do.
- Avoid introducing a generalized line-item event model before item-level clearing, returns, and availability policy exist.

---

## 3. Considered Options

| Option | Pros | Cons |
| :--- | :--- | :--- |
| **A. Orchestrate existing events from one workflow** | Preserves current posting and custody semantics; narrow implementation; easy to audit through child events. | Support views see two events for a mixed ticket unless they search by shared ticket reference. |
| **B. Add `deposit.ticket.accepted` as a new mixed event** | One event represents the full teller ticket. | Requires new mixed posting logic, mixed payload validation, reversal policy, and drawer projection handling. |
| **C. Collapse checks into `deposit.accepted` payload lines** | Single customer deposit event. | Overloads cash semantics and risks incorrectly projecting checks into drawer cash. |

---

## 4. Decision Outcome

**Chosen option: A. Orchestrate existing events from one workflow.**

The combined deposit ticket workflow records/posts existing child events under one server transaction:

- cash portion -> `deposit.accepted`
- check portion -> `check.deposit.accepted`
- optional check hold -> linked `hold.placed` against the check event only

The workflow uses a parent ticket idempotency key to derive deterministic child idempotency keys and a shared `reference_id` for support traceability.

### 4.1 Atomicity

The workflow runs in one outer database transaction. If any requested portion fails validation, posting, or hold placement, the full ticket rolls back.

### 4.2 Availability and holds

Cash is not included in the check hold cap. Event-level holds apply only to the check event and must not exceed the check total.

### 4.3 Reversal

Reversal remains child-event based in this slice. A mixed ticket that needs correction may reverse the cash event, the check event, or both according to existing reversal rules. Active holds linked to the check event continue to block reversal of that check event.

### 4.4 Deferrals

This decision does not add:

- item-specific holds, releases, or reversals
- check clearing, returns, or settlement lifecycle
- a first-class deposit-ticket table
- durable receipt/document storage
- one combined journal entry for mixed instruments

---

## 5. Implementation Notes

- Add `Core::OperationalEvents::Commands::AcceptDepositTicket` as the workflow orchestrator.
- Add a Branch teller HTML surface for combined deposits.
- Keep existing cash-only and check-only surfaces available.
- Use child event `reference_id` values to group ticket evidence.

---

## 6. References

- [deposit.accepted](../operational_events/deposit-accepted.md)
- [check.deposit.accepted](../operational_events/check-deposit-accepted.md)
