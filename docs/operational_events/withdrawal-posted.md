# Withdrawal posted (`withdrawal.posted`)

## Summary

Records that the institution **disbursed cash** to the customer and **debited** their demand deposit account for the stated amount. This is the inverse economic pattern of `deposit.accepted`: customer liability down, cash on hand down.

> **Naming:** ADR-0002 §5.1 lists `withdrawal.posted`. If the codebase uses an alternate string (e.g. `withdrawal.disbursed`), update this spec and the registry index in [README.md](README.md) in one change set so `event_type`, posting rules, and tests stay aligned.

## Registry

| Field | Value |
| ----- | ----- |
| **`event_type`** | `withdrawal.posted` |
| **Category** | Financial |
| **Phase** | Phase 1 (spec ahead of implementation). |

## Semantics

- **Must** reference an **open** deposit account via `source_account_id` (the account debited).
- **Must** carry positive `amount_minor_units` and supported `currency`.
- **Authorization:** Available balance (ledger minus active holds, per ADR-0004) **must** be at least the withdrawal amount before posting (enforce in `RecordEvent` and/or `PostEvent`).
- Cash-out path: typically requires an **open teller session** when drawer control is enabled.

## Persistence

| Column / concept | Required | Notes |
| ---------------- | -------- | ----- |
| `event_type` | Yes | `withdrawal.posted`. |
| `status` | Yes | `pending` → `posted`. |
| `business_date` | Yes | |
| `channel` | Yes | |
| `idempotency_key` | Yes | |
| `amount_minor_units` | Yes | Positive. |
| `currency` | Yes | MVP: USD. |
| `source_account_id` | Yes | Account debited. |
| `teller_session_id` | Conditional | On **`channel: teller`**, required (open session) when **`require_open_session_for_cash`** is true ([ADR-0014](../adr/0014-teller-sessions-and-control-events.md)). |
| `destination_account_id` | No | Not used for simple cash withdrawal. |
| `actor_id` | Optional | Nullable FK → **`operators`**. On teller JSON, set from **`X-Operator-Id`** ([ADR-0015](../adr/0015-teller-workspace-authentication.md)). |

## Lifecycle

Same pattern as `deposit.accepted`: **`pending`** until posting completes, then **`posted`**. No silent edits after `posted`.

## Posting

- **Yes** — balanced journal.
- **MVP legs (illustrative):** Debit GL **2110** (DDA liability, tagged with `deposit_account_id` = `source_account_id`); Credit GL **1110** (cash).
- Amounts mirror the deposit rule with debits/credits swapped vs `deposit.accepted`.

## Idempotency

- **Scope:** `(channel, idempotency_key)`.
- **Fingerprint:** `event_type`, `channel`, `idempotency_key`, `amount_minor_units`, `currency`, `source_account_id`; when the teller cash session gate applies, **`teller_session_id`** is included ([ADR-0014](../adr/0014-teller-sessions-and-control-events.md)).

## Reversals

- Reversed only via a **new** compensating event linked to the original (see [compensating-reversal.md](compensating-reversal.md)); original stays `posted`.

## Relationships

- **`source_account_id`:** account debited.
- **`teller_session_id`:** ties cash movement to drawer accountability.

## Module ownership

- **Record / validate:** `Core::OperationalEvents` + `Accounts` (and holds query for available balance).
- **Post:** `Core::Posting` / `Core::Ledger`.

## References

- [ADR-0002](../adr/0002-operational-event-model.md)
- [ADR-0004](../adr/0004-account-balance-model.md) — available balance.
- [ADR-0010](../adr/0010-ledger-persistence-and-seeded-coa.md)
- [ADR-0014](../adr/0014-teller-sessions-and-control-events.md) — open session gate, fingerprint
- [ADR-0015](../adr/0015-teller-workspace-authentication.md) — teller `X-Operator-Id`, `actor_id`

## Examples

```json
{
  "event_type": "withdrawal.posted",
  "channel": "teller",
  "idempotency_key": "wd-2026-04-22-001",
  "amount_minor_units": 5000,
  "currency": "USD",
  "source_account_id": 42,
  "teller_session_id": 7
}
```

**Posting sketch:** Dr 2110 (acct 42) / Cr 1110, amount 5_000.
