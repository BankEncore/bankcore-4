# Fee waived (`fee.waived`)

## Summary

Records a **full waiver** of a previously **posted** `fee.assessed` for the same account and amount. Posting **credits** customer DDA liability (GL **2110**) and **reduces** deposit service charge income (GL **4510**).

## Registry

| Field | Value |
| ----- | ----- |
| **`event_type`** | `fee.waived` |
| **Category** | Financial |
| **Phase** | Implemented ([ADR-0019](../adr/0019-event-catalog-and-fee-events.md)). |

## Semantics

- **`reference_id`** (string, numeric id) **required**: must equal the **`operational_events.id`** of a **posted** **`fee.assessed`** with the same `source_account_id` and `amount_minor_units`.
- At most **one posted** `fee.waived` per `reference_id` (MVP full waive only).

## Persistence

| Column / concept | Required | Notes |
| ---------------- | -------- | ----- |
| `reference_id` | Yes | Original `fee.assessed` event id. |

## Lifecycle

`pending` → `posted` via `PostEvent`.

## Posting

| Leg | GL | Side | `deposit_account_id` |
| --- | --- | --- | --- |
| 1 | 4510 | debit | nil |
| 2 | 2110 | credit | `source_account_id` |

## Idempotency

Fingerprint includes **`reference_id`** when present (required for `fee.waived`).

## Reversals

Not in `RecordReversal` allowlist; compensating path is this event type only.

## Module ownership

`Core::OperationalEvents::Commands::RecordEvent`, `Core::Posting::PostingRules::FeeWaived`.

## References

- [ADR-0019](../adr/0019-event-catalog-and-fee-events.md)
- [fee-assessed.md](fee-assessed.md)
