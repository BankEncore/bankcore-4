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

---

## 4. Phase 4.4 hold lifecycle and taxonomy

Phase 4.4 deepens holds for Branch CSR servicing without changing the no-GL invariant or adding partial-release semantics.

### 4.1 Hold lifecycle

Holds use these durable statuses:

| Status | Meaning |
| ------ | ------- |
| `active` | Hold currently reduces available balance. |
| `released` | Hold was manually released by an operator or servicing workflow. It no longer reduces available balance. |
| `expired` | Hold expired because its configured expiration business date was reached by a system process. It no longer reduces available balance. |

Lifecycle transitions:

- `active` → `released` is created by `Accounts::Commands::ReleaseHold` and a posted no-GL `hold.released` operational event.
- `active` → `expired` is created by `Accounts::Commands::ExpireDueHolds` as a system process.
- Released and expired holds are terminal in this slice. Reinstating a hold requires a new `hold.placed` event and a new `holds` row.
- Expiration must be idempotent: rerunning due-hold processing for the same business date must not create duplicate close events or mutate terminal holds.

Expiration event decision:

- The preferred Phase 4.4 implementation may use existing `hold.released` as the no-GL lifecycle-close event with `channel: system` and deterministic idempotency keys when the operational distinction can be carried by hold status and reason fields.
- Add a new `hold.expired` event type only if support, statements, or customer-facing history require expiry to be distinguishable from operator release at the immutable event-type level.
- Either path remains no-GL and must not call `Core::Posting::Commands::PostEvent`.

### 4.2 Hold type taxonomy

`holds` should distinguish the broad business reason for available-balance reduction:

| Hold type | Meaning |
| --------- | ------- |
| `deposit` | Availability hold linked to a deposit or other funds-availability decision. |
| `administrative` | Internal servicing hold not tied to a specific legal order or deposit event. |
| `legal` | Hold associated with garnishment, levy, court order, or similar legal restriction. |
| `channel_authorization` | Temporary channel authorization hold, such as a future card/ATM authorization. |

Phase 4.4 may store `hold_type` directly on `holds`. `deposit` holds remain the only type with first-class `placed_for_operational_event_id` semantics in this slice.

### 4.3 Reason taxonomy and explanations

`holds` should also carry operator/customer explanation metadata:

| Field | Purpose |
| ----- | ------- |
| `reason_code` | Controlled reason for reporting and customer-safe explanation. |
| `reason_description` | Optional staff-entered detail for internal servicing review. |
| `expires_on` | Optional business date when the hold becomes eligible for automatic expiration. |

Initial `reason_code` values:

| Reason code | Customer-safe explanation |
| ----------- | ------------------------- |
| `deposit_availability` | Funds are held while a recent deposit becomes available. |
| `customer_request` | Funds are held at customer request. |
| `fraud_review` | Funds are held while account activity is reviewed. |
| `legal_order` | Funds are restricted due to a legal order. |
| `manual_review` | Funds are held pending internal review. |
| `other` | Funds are held for another servicing reason recorded by staff. |

Customer-safe explanations should be generated from the controlled `reason_code`, not free-form staff notes. `reason_description` is internal by default and must not appear in customer-facing APIs unless a later redaction decision allows it.

### 4.4 Branch CSR display

Branch CSR account and holds screens should show:

- hold amount, currency, status, type, reason, placed date, optional expiration date, and linked deposit event when present
- whether the hold currently reduces available balance
- a customer-safe explanation based on `reason_code`
- audit references: placing/releasing/expiring operational event ids, channel, actor, and idempotency key where available

### 4.5 Explicit deferrals

Phase 4.4 does **not** add:

- partial hold release
- hold amount adjustment
- multiple active amounts under one hold row
- cascade release when reversing deposits
- Reg CC or product-driven availability schedule calculation
- GL posting for holds

Partial release or adjustment requires a separate ADR before implementation because it changes amount semantics, idempotency fingerprints, available-balance calculations, Branch confirmation copy, and likely operational-event taxonomy.
