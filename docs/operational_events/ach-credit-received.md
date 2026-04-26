# ACH credit received (`ach.credit.received`)

## Summary

Records that an inbound ACH credit item has been accepted from structured receipt input and posted to one open deposit account.

## Registry

| Field | Value |
| ----- | ----- |
| **`event_type`** | `ach.credit.received` |
| **Category** | Financial (ADR-0028 §2.1) |
| **Phase** | Implemented in Phase 4.7 as a narrow structured ACH receipt command. |
| **Lifecycle** | `pending_to_posted` |
| **Allowed channels** | `batch` |
| **Financial impact** | `gl_posting` |
| **Customer visible** | Yes |
| **Statement visible** | Yes |
| **Payload schema** | `docs/operational_events/ach-credit-received.md` |
| **Support search keys** | `source_account_id`, `reference_id`, `idempotency_key` |

## Semantics

- Must be produced by `Integration::Ach::Commands::IngestReceiptFile` over structured file/batch/item input.
- Must reference an open `deposit_accounts` row through `source_account_id`.
- Must carry a positive `amount_minor_units` and `currency` of `USD`.
- Must use channel `batch`.
- Full NACHA parsing, ACH debits, returns, NOCs, prenotes, receiver-name matching, cutoff queues, and file/batch persistence are deferred.

## Persistence

| Column / concept | Required | Notes |
| ---------------- | -------- | ----- |
| `event_type` | Yes | Literal `ach.credit.received`. |
| `status` | Yes | `pending` until posting succeeds; then `posted`. |
| `business_date` | Yes | Current open business date only. |
| `channel` | Yes | Literal `batch` for this slice. |
| `idempotency_key` | Yes | `ach-credit-received:{file_id}:{batch_id}:{item_id}`. |
| `reference_id` | Yes | `ach:{file_id}:{batch_id}:{item_id}` for support search. |
| `amount_minor_units` | Yes | Positive integer. |
| `currency` | Yes | `USD`. |
| `source_account_id` | Yes | FK to credited deposit account. |

## Lifecycle

1. `pending` — Row inserted for an accepted ACH credit item.
2. `posted` — `PostEvent` committed the settlement and DDA journal lines.

Failed posting leaves the event `pending` for support and EOD visibility.

## Posting

- Runs through `Core::Posting::Commands::PostEvent`.
- Legs: Debit GL `1120` ACH Settlement; Credit GL `2110` DDA liability.
- The `2110` line carries `journal_lines.deposit_account_id = source_account_id`.

## Idempotency

- Scope: `(channel, idempotency_key)`.
- Deterministic key: `ach-credit-received:{file_id}:{batch_id}:{item_id}`.
- Material fields: `event_type`, `channel`, `idempotency_key`, `reference_id`, `business_date`, `amount_minor_units`, `currency`, and `source_account_id`.
- Replays of a posted matching item return existing evidence without creating another event or journal.
- Replays of a pending matching item post the existing event.
- Replays with materially different fields return an item-level idempotency mismatch.

## Reversals

This event is reversible through `posting.reversal` under the existing supervisor-controlled reversal path. ACH returns are not modeled as reversals in this slice.

## Relationships

- `source_account_id`: credited deposit account.
- `reference_id`: structured support key joining the operational event back to file/batch/item identifiers.

## Module ownership

- Input orchestration: `Integration::Ach`.
- Account lookup: `Accounts::Queries::FindDepositAccountByAccountNumber`.
- Event durability: `Core::OperationalEvents`.
- Posting and journals: `Core::Posting` and `Core::Ledger`.

## References

- [ADR-0028](../adr/0028-ach-receipt-ingestion.md) — ACH receipt ingestion.
- [ADR-0002](../adr/0002-operational-event-model.md) — operational events and idempotency.
- [ADR-0012](../adr/0012-posting-rule-registry-and-journal-subledger.md) — posting registry.

## Examples

```json
{
  "event_type": "ach.credit.received",
  "channel": "batch",
  "idempotency_key": "ach-credit-received:file-20260425-001:batch-1:trace-091000019-000001",
  "reference_id": "ach:file-20260425-001:batch-1:trace-091000019-000001",
  "amount_minor_units": 12500,
  "currency": "USD",
  "source_account_id": 42
}
```

Posting sketch: Dr `1120` / Cr `2110` (`deposit_account_id` on Cr line = `source_account_id`).
