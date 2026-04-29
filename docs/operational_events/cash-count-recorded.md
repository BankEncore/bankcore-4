# cash.count.recorded

## Summary

Records that an operator counted a Cash-domain location and captured the expected and counted custody balance.

## Registry

| Field | Value |
| ----- | ----- |
| **event_type** | `cash.count.recorded` |
| **Category** | `operational` |
| **Lifecycle** | `posted_immediately` |
| **Allowed channels** | `teller`, `branch`, `system` |
| **Financial impact** | `no_gl` |
| **Customer visible** | No |
| **Statement visible** | No |
| **Payload schema** | `docs/operational_events/cash-count-recorded.md` |
| **Support search keys** | `reference_id`, `actor_id` |

## Semantics

Counts are append-oriented evidence. A count may create a `cash_variance`; GL adjustment is separate through `cash.variance.posted`.

## Persistence

`reference_id` is the numeric `cash_counts.id`; amount and currency mirror the counted amount.

## Lifecycle

Cash commands create this row directly as `posted`.

## Posting

No GL posting.

## Idempotency

The deterministic key is `cash-count-recorded:<cash_count_id>`.

## Reversals

Corrections use a new count and, if needed, a new approved variance.

## Relationships

`cash_counts.operational_event_id` points to this event.

## Module ownership

`Cash` owns count and variance creation. `Core::OperationalEvents` owns the event row.

## References

[ADR-0031](../adr/0031-cash-inventory-and-management.md)

## Examples

```json
{
  "event_type": "cash.count.recorded",
  "channel": "branch",
  "reference_id": "200",
  "amount_minor_units": 99500,
  "currency": "USD"
}
```
