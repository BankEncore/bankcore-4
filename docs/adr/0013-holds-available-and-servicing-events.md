# ADR-0013: Holds, available balance, and servicing operational events

**Status:** Accepted  
**Date:** 2026-04-23  
**Aligns with:** [ADR-0004](0004-account-balance-model.md), [ADR-0002](0002-operational-event-model.md)

---

## 1. Decision

- **`holds`** table is owned by **`Accounts`**. Active holds reduce **available** balance; they do not post GL journals.
- **`hold.placed`** / **`hold.released`** are persisted as `operational_events` rows with **`posted`** status at creation (no `PostEvent` path). Commands: **`Accounts::Commands::PlaceHold`** and **`Accounts::Commands::ReleaseHold`**.
- **Available** for authorization: `Accounts::Services::AvailableBalanceMinorUnits` = ledger on GL **2110** filtered by `journal_lines.deposit_account_id` minus active hold amounts ([ADR-0012](0012-posting-rule-registry-and-journal-subledger.md) subledger).

---

## 2. Consequences

- `withdrawal.posted` and `transfer.completed` **`RecordEvent`** reject when available &lt; amount.

---

## 3. Deposit-linked holds (P3-1)

**Semantics**

- A hold **may** optionally reference exactly one **posted** financial operational event of type **`deposit.accepted`** via **`holds.placed_for_operational_event_id`** → `operational_events.id`.
- The deposit’s **`source_account_id`** must equal the hold’s **`deposit_account_id`** (same DDA). Currency must remain **USD** and consistent with the deposit event and account conventions.
- **Multiple** active holds may reference the same deposit as long as the **sum** of their amounts does not exceed the deposit event’s **`amount_minor_units`** (prevents over-holding a single deposit).

**Validation (`PlaceHold`)**

- If `placed_for_operational_event_id` is present: load the event (under row lock when creating a new hold), require **`deposit.accepted`** and **`posted`**, account match, currency match, and **sum(active holds for that event) + new hold amount ≤ deposit amount**.
- Idempotent replays of **`PlaceHold`** must match the same optional link as persisted on the **`holds`** row.

**Reversal interaction**

- **`RecordReversal`** for a **`deposit.accepted`** original is **rejected** while **any** hold remains **`active`** with **`placed_for_operational_event_id`** equal to that deposit’s id. Operators must **release** (or expire, when implemented) those holds first. **Cascade-release** on reversal was considered and deferred (clearer invariant and less coupling in this slice).

**Non-goals (this slice)**

- **Reg CC** availability schedules, collected-funds engine, or **`expires_at`**-driven expiry jobs.
- **Partial** hold release or hold amount adjustment beyond full **release** path.

**Alignment with ADR-0004**

- Deposit-linked holds remain **non-GL** servicing; they only affect **available** balance per [ADR-0004](0004-account-balance-model.md) §5–6.
