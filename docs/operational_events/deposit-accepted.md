# Deposit accepted (`deposit.accepted`)

## Summary

Records that the institution **accepted** a cash deposit and intends to **credit** a specific demand deposit account for the stated amount. Posting completes the economic booking (cash asset up, customer liability up).

## Registry

| Field | Value |
| ----- | ----- |
| **`event_type`** | `deposit.accepted` |
| **Category** | Financial (ADR-0002 §5.1) |
| **Phase** | Implemented; **`actor_id`** on teller JSON per [ADR-0015](../adr/0015-teller-workspace-authentication.md). **`teller_session_id`** required for teller-channel cash when [ADR-0014](../adr/0014-teller-sessions-and-control-events.md) gate is on. |
| **Lifecycle** | `pending_to_posted` |
| **Allowed channels** | `teller`, `api`, `batch` |
| **Financial impact** | `gl_posting` |
| **Customer visible** | Yes |
| **Statement visible** | Yes |
| **Payload schema** | `docs/operational_events/deposit-accepted.md` |
| **Support search keys** | `source_account_id`, `actor_id`, `teller_session_id` |

## Semantics

- **Must** reference an **open** `deposit_accounts` row via `source_account_id` (the account being credited).
- **Must** carry a positive `amount_minor_units` and supported `currency` (MVP: USD).
- Represents **cash-in** tender only. Combined cash/check deposit tickets use this event for the cash portion and `check.deposit.accepted` for the check portion ([ADR-0043](../adr/0043-combined-cash-check-deposit-workflow.md)).

## Persistence

| Column / concept | Required | Notes |
| ---------------- | -------- | ----- |
| `event_type` | Yes | Literal `deposit.accepted`. |
| `status` | Yes | `pending` until posting succeeds; then `posted`. Never “un-posted” via row mutation. |
| `business_date` | Yes | From `Core::BusinessDate` when not supplied. |
| `channel` | Yes | e.g. `teller`; scopes idempotency. |
| `idempotency_key` | Yes | Opaque client key; unique with `channel`. |
| `amount_minor_units` | Yes | Positive integer (ADR-0008 minor units). |
| `currency` | Yes | MVP: `USD`. |
| `source_account_id` | Yes | FK → `deposit_accounts` (account credited). |
| `teller_session_id` | Conditional | On **`channel: teller`**, required (open session) when **`config.x.teller.require_open_session_for_cash`** is true ([ADR-0014](../adr/0014-teller-sessions-and-control-events.md)); optional for other channels. |
| `actor_id` | Optional | Nullable FK → **`operators`**. On **`POST /teller/operational_events`**, set from **`X-Operator-Id`** when present ([ADR-0015](../adr/0015-teller-workspace-authentication.md)); other channels may omit until they authenticate. |
| `reference_id` | Optional | Support grouping key. Combined deposit tickets set a shared `deposit-ticket:<idempotency_key>` reference on child cash/check events. |

## Lifecycle

1. **`pending`** — Row inserted by `RecordEvent`; no balanced journal yet (or batch not `posted`).
2. **`posted`** — `PostEvent` committed: posting batch `posted`, journal exists, event updated in same transaction.

Failed posting leaves the event **`pending`** (ADR-0002 §3.2: do not overload `operational_events.status` with `failed`).

## Posting

- **Runs through** `Core::Posting::Commands::PostEvent` (or equivalent posting rule).
- **MVP legs (illustrative):** Debit GL **1110** (cash in vaults / drawer); Credit GL **2110** (DDA liability).
- **Subledger:** Liability line **must** carry customer attribution (e.g. `journal_lines.deposit_account_id` → same as `source_account_id`) once per-account balance is required for Phase 1.

## Idempotency

- **Scope:** `(channel, idempotency_key)` at most one row (ADR-0002 §7.3).
- **Fingerprint (material fields):** include `event_type`, `channel`, `idempotency_key`, `amount_minor_units`, `currency`, `source_account_id`, and `reference_id` when present. When the teller cash session gate applies, **`teller_session_id`** is included ([ADR-0014](../adr/0014-teller-sessions-and-control-events.md)).

## Reversals

- Original row stays **`posted`** after a reversal (ADR-0002 §6).
- Correction is a **new** operational event with compensating journal; see [compensating-reversal.md](compensating-reversal.md). Supervisor approval may be required (Phase 1 RBAC).

## Relationships

- **`source_account_id`:** account credited.
- **`teller_session_id`:** drawer correlation; required for teller cash when policy enabled ([ADR-0014](../adr/0014-teller-sessions-and-control-events.md)).
- **`reference_id`:** optional ticket grouping key when recorded by a combined deposit workflow.

## Module ownership

- **Record / validate:** `Core::OperationalEvents` (with `Accounts` invariants for open account).
- **Post:** `Core::Posting` (posting rules); journal rows `Core::Ledger`.

## References

- [ADR-0002](../adr/0002-operational-event-model.md) — lifecycle, idempotency, reversals.
- [ADR-0010](../adr/0010-ledger-persistence-and-seeded-coa.md) — tables, GL seed.
- [ADR-0011](../adr/0011-accounts-deposit-vertical-slice-mvp.md) — slice 1 deposit path.
- [ADR-0014](../adr/0014-teller-sessions-and-control-events.md) — open session gate for teller cash, fingerprint.
- [ADR-0015](../adr/0015-teller-workspace-authentication.md) — teller JSON `X-Operator-Id`, `actor_id` → `operators`.
- [ADR-0043](../adr/0043-combined-cash-check-deposit-workflow.md) — combined cash/check workflow orchestration.

## Examples

**Record (conceptual JSON):**

```json
{
  "event_type": "deposit.accepted",
  "channel": "teller",
  "idempotency_key": "idem-2026-04-22-001",
  "amount_minor_units": 10000,
  "currency": "USD",
  "source_account_id": 42
}
```

**Posting sketch:** Dr 1110 / Cr 2110 (`deposit_account_id` on Cr line = 42), amount 10_000.
