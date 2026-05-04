# ADR-0039: Teller session drawer custody projection

**Status:** Accepted  
**Date:** 2026-05-03  
**Decision Type:** Cash custody / teller session balancing  
**Aligns with:** [ADR-0002](0002-operational-event-model.md), [ADR-0014](0014-teller-sessions-and-control-events.md), [ADR-0018](0018-business-date-close-and-posting-invariant.md), [ADR-0020](0020-teller-drawer-variance-gl-posting.md), [ADR-0031](0031-cash-inventory-and-management.md), [ADR-0037](0037-internal-staff-authorized-surfaces.md), [module catalog](../architecture/bankcore-module-catalog.md)

---

## 1. Context and Problem Statement

BankCORE now has two related branch cash views:

- **Teller session expected cash**: the amount a teller should count at close for a specific session.
- **Cash drawer custody balance**: the Cash-domain balance for the linked `teller_drawer` `cash_location`.

ADR-0014 defines teller expected cash as session-derived, and ADR-0031 defines `Cash` as the owner of physical custody balances. ADR-0031 intentionally deferred whether posted teller-channel cash events should automatically adjust linked drawer `cash_balances`.

That deferral now leaves a gap. A posted teller deposit or withdrawal changes the teller's accountable drawer cash, but Cash-domain drawer balances are only updated by Cash-native movements and counts. At the same time, session expected cash must not count pending operational events because posted state is the effective financial and operational boundary for cash-affecting teller transactions.

This ADR resolves the deferred policy decision and defines how teller sessions, posted teller cash events, cash drawer custody, reversals, and vault/drawer movements fit together.

---

## 2. Decision Drivers

- Preserve the single financial write path: customer financial effects still flow through `Core::OperationalEvents` and `Core::Posting`.
- Keep Cash as the owner of physical custody balances and rebuildable custody projections.
- Avoid two independent drawer truths by making posted teller cash events an explicit input to Cash custody projection.
- Make `CloseSession` audit-safe by computing expected cash server-side.
- Keep reversals forward-only and idempotent.
- Keep session responsibility explicit when vault/drawer movements occur during an open session.
- Avoid overloading `cash_movements` with synthetic customer transaction rows.

---

## 3. Considered Options

| Option | Pros | Cons |
| :--- | :--- | :--- |
| **No teller-event projection into Cash** | Lowest coupling; preserves ADR-0031 deferral. | Drawer custody can drift from posted teller activity; close-time cash control remains incomplete. |
| **Represent teller cash events as synthetic `cash_movements`** | Single Cash movement table for all drawer deltas. | Blurs customer financial events with custody movements; makes reversals and source/destination semantics awkward. |
| **Cash-owned teller event projection table** | Clear ownership, idempotent projection marker, rebuildable custody input, separate from Cash-native movements. | Adds another Cash-owned table and a posting-boundary hook. |

---

## 4. Decision Outcome

**Chosen Option: Cash-owned teller event projection table.**

Posted `deposit.accepted` and `withdrawal.posted` events with `teller_session_id` and a session-linked drawer will project into the linked session drawer's Cash custody balance. The projection is Cash-owned, append-only, and idempotent. It records the custody delta caused by a posted operational event without pretending that the customer event is a Cash movement.

This decision resolves the open product decision in ADR-0031 §5.2.

### 4.1 Ownership

- `Teller` owns `teller_sessions`, session lifecycle, expected cash calculation, actual cash count, and variance workflow.
- `Cash` owns `cash_locations`, `cash_balances`, `cash_movements`, `cash_counts`, and teller-event custody projection rows.
- `Core::OperationalEvents` owns durable business events and reversal linkage.
- `Core::Posting` owns the posting boundary. It invokes a Cash-owned projector in the same database transaction when an eligible event successfully becomes posted, but it must not contain Cash balance rules directly.

### 4.2 Posted teller event projection

A Cash-owned projection command accepts:

```text
input: posted operational_event_id
supported events:
  - deposit.accepted with teller_session_id and a session-linked drawer
  - withdrawal.posted with teller_session_id and a session-linked drawer
  - posting.reversal when reversal_of_event is a teller cash event
```

For `deposit.accepted`, Cash applies a positive drawer delta to the original session's linked `cash_location_id`.

For `withdrawal.posted`, Cash applies a negative drawer delta to the original session's linked `cash_location_id`.

For `posting.reversal`, Cash applies the opposite delta of the original teller cash event to the original event's `teller_session_id` and linked drawer. This uses the original event's session and drawer even if that session is already closed. Reversal projection must be tied to the reversal operational event id, not by mutating or deleting the original projection row.

Projection only runs after the operational event is posted. Pending events must never affect drawer custody balance.

Projection runs inside the same database transaction as `Core::Posting::Commands::PostEvent`. If the Cash projector cannot create the idempotency marker or apply the drawer balance delta, posting must roll back. BankCORE intentionally chooses strong consistency here; if a future implementation decouples projection asynchronously, that change must add an explicit repair/replay path and update this ADR.

### 4.3 Idempotency and audit table

Add a Cash-owned projection table such as `cash_teller_event_projections`.

Recommended fields:

- `operational_event_id` — unique FK to the posted event that caused this projection.
- `reversal_of_operational_event_id` — nullable FK for reversal projections.
- `teller_session_id` — FK to the session responsible for the drawer.
- `cash_location_id` — FK to the linked drawer location.
- `projection_type` — enum-like string, for example `teller_cash_event` or `teller_cash_reversal`.
- `event_type` — copied event type for support evidence.
- `amount_minor_units` — positive event amount.
- `delta_minor_units` — signed drawer custody delta.
- `currency` — initially `USD`.
- `business_date`.
- `applied_at` — timestamp set when the Cash projector writes the projection row inside the posting transaction.
- timestamps.

`operational_event_id` must be unique so replay of `PostEvent`, application retry, or duplicate projector invocation cannot double-apply drawer custody balance.

The projection row is both an idempotency marker and rebuild evidence. Cash location balances remain persisted snapshots that can be rebuilt from Cash-native movements/counts plus these projection rows.

### 4.4 Rebuild ordering

Cash balances are rebuildable by replaying Cash-owned evidence for each `cash_location_id` in deterministic order. Rebuild inputs are:

- completed `cash_movements`;
- `cash_teller_event_projections`;
- `cash_counts`.

Replay order must be governed by:

1. `business_date`;
2. effective timestamp (`completed_at` for movements, `applied_at` for teller-event projections, `created_at` for counts);
3. type priority for rows with identical timestamps: movements, then teller-event projections, then counts;
4. source table primary key within each replay source after type priority is applied.

Movements and teller-event projections apply signed deltas. Counts are reset points: a count overwrites the replayed balance for that location at that point in the sequence and subsequent movements/projections apply after it.

### 4.5 Opening cash and expected cash

Add `opening_cash_minor_units` to `teller_sessions`.

`Teller::Commands::OpenSession` snapshots the linked drawer's current Cash balance into `opening_cash_minor_units` at open. This makes close meaningful when a drawer was funded before the session opened.

`Teller::Queries::ExpectedCashForSession` computes:

```text
opening_cash_minor_units
+ posted, non-reversed deposit.accepted deltas for the session
- posted, non-reversed withdrawal.posted deltas for the session
+/- completed Cash movements explicitly attributed to the session
```

The query must ignore pending teller events. Reversed teller cash events are excluded from expected cash because the original event is no longer effective for the session. Reversal projection corrects drawer custody, not expected cash directly.

Only opening cash, posted non-reversed teller cash events, and explicitly session-attributed completed Cash movements affect expected cash. Cash counts, cash variances, and drawer variance GL events do not change expected cash; they are observed/control evidence, not expectation inputs.

### 4.6 Close session ownership

`Teller::Commands::CloseSession` computes expected cash internally. Callers provide only:

```json
{
  "teller_session_close": {
    "teller_session_id": 123,
    "actual_cash_minor_units": 100000
  }
}
```

Branch HTML and JSON `/teller` close flows must not supply trusted `expected_cash_minor_units`. The command persists computed expected cash, actual cash, and variance on `teller_sessions`.

### 4.7 Session-attributed Cash movements

Add optional `teller_session_id` to relevant `cash_movements`.

Vault-to-drawer and drawer-to-vault movements affect session expected cash only when explicitly tied to a teller session. BankCORE must not infer session attribution solely from drawer location and time window.

When present, `cash_movements.teller_session_id` must reference an open session for the affected drawer at movement completion time. The referenced session's `cash_location_id` must match the teller-drawer location affected by the movement:

- vault to session drawer: positive expected cash delta.
- session drawer to vault: negative expected cash delta.

Attribution is validated at completion time, including approval completion for movements that begin in `pending_approval`. Completed session-attributed movements are included in `ExpectedCashForSession` with the signed deltas above.

Cash movements remain Cash-native custody records. Teller event projections remain separate projection rows. Reversal or correction of a Cash movement remains Cash-native through compensating movements, counts, or approved adjustments; movement rows must not be silently edited to change session responsibility after completion.

---

## 5. Worked Examples

### 5.1 Posted teller deposit

1. Teller session `10` opens on drawer location `20` with `opening_cash_minor_units = 50000`.
2. Teller records `deposit.accepted` for `10000` with `teller_session_id = 10` and a linked drawer.
3. The event is `pending`; session expected cash and drawer custody do not change.
4. `Core::Posting::Commands::PostEvent` posts the event and invokes the Cash projector in the same transaction.
5. The Cash projector inserts one projection row keyed by that operational event id:

```text
teller_session_id: 10
cash_location_id: 20
event_type: deposit.accepted
delta_minor_units: +10000
```

6. Drawer `cash_balance` increases by `10000`.
7. Session expected cash is `50000 + 10000 = 60000`.

### 5.2 Posted teller withdrawal reversal

1. Teller session `10` posts `withdrawal.posted` for `2500`.
2. Cash projection applies `delta_minor_units = -2500`.
3. A supervisor posts `posting.reversal` for that withdrawal event.
4. Cash projection for the reversal uses the original event's session and drawer, then applies `delta_minor_units = +2500`.
5. The original event remains immutable and marked reversed by the reversal event.

### 5.3 Vault funding during an open session

1. Session `10` is open on drawer location `20`.
2. A vault-to-drawer `cash_movement` for `30000` completes with `teller_session_id = 10`.
3. Cash movement projection updates drawer custody through existing Cash movement rules.
4. Expected cash for session `10` includes `+30000`.

If the same movement lacks `teller_session_id`, it still changes drawer custody, but it does not change session expected cash.

---

## 6. Consequences

### Positive

- Drawer custody balances include posted teller deposits and withdrawals without turning customer events into synthetic Cash movements.
- Session expected cash becomes server-computed and explainable.
- Reversals correct both GL/account effects and drawer custody effects.
- Cash balances remain rebuildable from Cash-owned evidence.
- Session responsibility for vault/drawer movements is explicit.

### Negative

- Adds schema and projection code in the Cash domain.
- `Core::Posting::Commands::PostEvent` gains a post-success integration point to a Cash-owned projector.
- Existing JSON close clients must stop sending or relying on `expected_cash_minor_units`.

### Neutral

- This does not change GL posting rules for deposits, withdrawals, or reversals.
- This does not introduce denomination tracking.
- This does not make `cash_balances` financial truth; GL remains the financial reporting truth.

---

## 7. Implementation Plan

1. Fix `Teller::Queries::ExpectedCashForSession` to use only posted, non-reversed teller cash events.
2. Add `teller_sessions.opening_cash_minor_units`.
3. Snapshot linked drawer Cash balance in `Teller::Commands::OpenSession`.
4. Change `Teller::Commands::CloseSession` to compute expected cash internally; update Branch HTML and JSON `/teller` close callers.
5. Add `cash_teller_event_projections` or equivalent Cash-owned projection table with unique `operational_event_id`.
6. Add optional `cash_movements.teller_session_id` and validations for session-attributed vault/drawer movements.
7. Add a Cash-owned projector for eligible posted teller cash events and reversals.
8. Invoke the projector from `PostEvent` within the posting transaction.
9. Add tests for pending events, posted events, idempotent replays, reversals, opening cash, JSON close, and session-attributed cash movements.

---

## 8. Related Documents

- [ADR-0014: Teller sessions and control operational events](0014-teller-sessions-and-control-events.md)
- [ADR-0020: Teller drawer variance GL posting](0020-teller-drawer-variance-gl-posting.md)
- [ADR-0031: Cash inventory and management](0031-cash-inventory-and-management.md)
- [ADR-0037: Internal staff authorized surfaces](0037-internal-staff-authorized-surfaces.md)
- [Branch cash operating model](../concepts/301-branch-level-cash-tracking.md)
