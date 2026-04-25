# Interest posted (`interest.posted`)

## Summary

Records full payout of a posted `interest.accrued` event into the customer DDA. Posting clears accrued interest payable (GL **2510**) and credits DDA liability (GL **2110**).

## Registry

| Field | Value |
| ----- | ----- |
| **`event_type`** | `interest.posted` |
| **Category** | Financial |
| **Phase** | P3-2 first vertical slice ([ADR-0021](../adr/0021-interest-accrual-and-payout-slice.md)). |
| **Lifecycle** | `pending_to_posted` |
| **Allowed channels** | `system` |
| **Financial impact** | `gl_posting` |
| **Customer visible** | Yes |
| **Statement visible** | Yes |
| **Payload schema** | `docs/operational_events/interest-posted.md` |
| **Support search keys** | `source_account_id`, `reference_id` |

## Semantics

- **Must** use `channel: "system"`.
- **`reference_id`** (string, numeric id) **required**: must equal the `operational_events.id` of a **posted** `interest.accrued` with the same `source_account_id`, `amount_minor_units`, and `currency`.
- At most **one posted** `interest.posted` per referenced accrual (MVP full payout only).

## Persistence

| Column / concept | Required | Notes |
| ---------------- | -------- | ----- |
| `reference_id` | Yes | Original `interest.accrued` event id. |

## Lifecycle

`pending` → `posted` via `PostEvent`.

## Posting

| Leg | GL | Side | `deposit_account_id` |
| --- | --- | --- | --- |
| 1 | 2510 | debit | `source_account_id` |
| 2 | 2110 | credit | `source_account_id` |

## Idempotency

Fingerprint includes **`reference_id`** when present (required for `interest.posted`).

## Reversals

Reversible via `posting.reversal`. The referenced `interest.accrued` remains protected from reversal while this posted payout references it.

## Module ownership

`Core::OperationalEvents::Commands::RecordEvent`, `Core::Posting::PostingRules::InterestPosted`.

## References

- [ADR-0021](../adr/0021-interest-accrual-and-payout-slice.md)
- [interest-accrued.md](interest-accrued.md)
