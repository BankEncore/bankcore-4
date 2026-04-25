# Transfer completed (`transfer.completed`)

## Summary

Records an **internal transfer** of funds between two deposit accounts (same institution, same currency in MVP): liability decreases on the source account and increases on the destination account, with **no** cash GL leg.

## Registry

| Field | Value |
| ----- | ----- |
| **`event_type`** | `transfer.completed` |
| **Category** | Financial (ADR-0002 §5.1) |
| **Phase** | Phase 1 (spec ahead of implementation). |
| **Lifecycle** | `pending_to_posted` |
| **Allowed channels** | `teller`, `api`, `batch` |
| **Financial impact** | `gl_posting` |
| **Customer visible** | Yes |
| **Statement visible** | Yes |
| **Payload schema** | `docs/operational_events/transfer-completed.md` |
| **Support search keys** | `source_account_id`, `destination_account_id`, `actor_id` |

## Semantics

- **Both** `source_account_id` and `destination_account_id` **must** be set to **distinct**, **open** deposit accounts.
- **Same currency** as both accounts (MVP: enforce USD).
- **Positive** `amount_minor_units`.
- **Authorization:** Source account **available** balance must cover the amount (ADR-0004).
- Optional: policy that both accounts belong to the same branch or party—document when introduced.

## Persistence

| Column / concept | Required | Notes |
| ---------------- | -------- | ----- |
| `event_type` | Yes | `transfer.completed`. |
| `status` | Yes | `pending` → `posted`. |
| `business_date`, `channel`, `idempotency_key` | Yes | |
| `amount_minor_units`, `currency` | Yes | |
| `source_account_id` | Yes | From account (debited in economic sense on liability). |
| `destination_account_id` | Yes | To account (credited). |
| `teller_session_id` | Optional | May be omitted for internal transfer; policy choice. |
| `actor_id` | Optional | Nullable FK → **`operators`**. On teller JSON, set from **`X-Operator-Id`** ([ADR-0015](../adr/0015-teller-workspace-authentication.md)). |

> **`destination_account_id`** on `operational_events` is required for this type once the column exists (ADR-0002 §8.1 roadmap).

## Lifecycle

`pending` → `posted` when posting succeeds; immutability after `posted` per ADR-0002 §6.

## Posting

- **Yes** — one balanced journal entry (single batch).
- **MVP legs (illustrative):** Debit GL **2110** with subledger **source** account; Credit GL **2110** with subledger **destination** account. **Both** liability lines must carry distinct `deposit_account_id` (or equivalent subledger) so per-customer balances reconcile; posting only to aggregate 2110 without subledger is **not** sufficient for two-party transfers.

## Idempotency

- **Scope:** `(channel, idempotency_key)`.
- **Fingerprint:** include `event_type`, `channel`, `idempotency_key`, `amount_minor_units`, `currency`, `source_account_id`, `destination_account_id`.

## Reversals

- Compensating reversal event (see [compensating-reversal.md](compensating-reversal.md)); original transfer row remains `posted`.

## Relationships

- Two deposit accounts; no cash account for the simple internal transfer.

## Module ownership

- **Record / validate:** `Core::OperationalEvents` + `Accounts`.
- **Post:** `Core::Posting` / `Core::Ledger`.

## References

- [ADR-0002](../adr/0002-operational-event-model.md)
- [ADR-0004](../adr/0004-account-balance-model.md)
- [ADR-0010](../adr/0010-ledger-persistence-and-seeded-coa.md)
- [ADR-0015](../adr/0015-teller-workspace-authentication.md) — teller `X-Operator-Id`, `actor_id`

## Examples

```json
{
  "event_type": "transfer.completed",
  "channel": "teller",
  "idempotency_key": "xfer-2026-04-22-001",
  "amount_minor_units": 3000,
  "currency": "USD",
  "source_account_id": 42,
  "destination_account_id": 99
}
```

**Posting sketch:** Dr 2110 + `deposit_account_id` 42 / Cr 2110 + `deposit_account_id` 99, amount 3_000.
