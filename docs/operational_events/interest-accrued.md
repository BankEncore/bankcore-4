# Interest accrued (`interest.accrued`)

## Summary

Records ledger-recognized deposit interest expense and accrued payable for one deposit account. This event is already rounded to currency minor units; raw microcent/sub-minor accrual belongs to a future engine accumulator, not the ledger.

## Registry

| Field | Value |
| ----- | ----- |
| **`event_type`** | `interest.accrued` |
| **Category** | Financial |
| **Phase** | P3-2 first vertical slice ([ADR-0021](../adr/0021-interest-accrual-and-payout-slice.md)). |
| **Lifecycle** | `pending_to_posted` |
| **Allowed channels** | `system` |
| **Financial impact** | `gl_posting` |
| **Customer visible** | No |
| **Statement visible** | No |
| **Payload schema** | `docs/operational_events/interest-accrued.md` |
| **Support search keys** | `source_account_id`, `reference_id` |

## Semantics

- **Must** use `channel: "system"`.
- **Must** reference an **open** `deposit_accounts` row via `source_account_id`.
- **Must** carry positive `amount_minor_units` and `currency` (MVP: USD).
- Represents the posting-boundary accrual amount, not raw daily computational accrual.

## Persistence

| Column / concept | Required | Notes |
| ---------------- | -------- | ----- |
| `reference_id` | No | Unused on accrual. |

## Lifecycle

`pending` → `posted` via `PostEvent`.

## Posting

| Leg | GL | Side | `deposit_account_id` |
| --- | --- | --- | --- |
| 1 | 5100 | debit | nil |
| 2 | 2510 | credit | `source_account_id` |

## Idempotency

Fingerprint: `event_type`, `channel`, `idempotency_key`, `amount_minor_units`, `currency`, `source_account_id`.

## Reversals

Reversible via `posting.reversal` only when no posted `interest.posted` references this accrual in `reference_id`.

## Module ownership

`Core::OperationalEvents::Commands::RecordEvent`, `Core::Posting::PostingRules::InterestAccrued`.

## References

- [ADR-0021](../adr/0021-interest-accrual-and-payout-slice.md)
- [ADR-0012](../adr/0012-posting-rule-registry-and-journal-subledger.md)
- [interest-posted.md](interest-posted.md)
