# cash.movement.completed

## Summary

Records a completed internal custody movement between Cash-domain locations such as a branch vault and teller drawer. It does not post to GL.

## Registry

| Field | Value |
| ----- | ----- |
| **event_type** | `cash.movement.completed` |
| **Category** | `operational` |
| **Lifecycle** | `posted_immediately` |
| **Allowed channels** | `teller`, `branch`, `system` |
| **Financial impact** | `no_gl` |
| **Customer visible** | No |
| **Statement visible** | No |
| **Payload schema** | `docs/operational_events/cash-movement-completed.md` |
| **Support search keys** | `reference_id`, `actor_id` |

## Semantics

The event confirms custody moved inside institutional cash ownership. It must not call `PostEvent` or create journal lines.

## Persistence

`reference_id` is the numeric `cash_movements.id`; amount and currency mirror the movement row.

## Lifecycle

Cash commands create this row directly as `posted` after balances are updated.

## Posting

No GL posting. Internal vault/drawer movement remains within aggregate cash account `1110`.

## Idempotency

The deterministic key is `cash-movement-completed:<cash_movement_id>`.

## Reversals

Corrections use a compensating Cash movement, not `posting.reversal`.

## Relationships

`cash_movements.operational_event_id` points to this event.

## Module ownership

`Cash` owns movement validation and balance projection. `Core::OperationalEvents` owns the durable event row.

## References

[ADR-0031](../adr/0031-cash-inventory-and-management.md)

## Examples

```json
{
  "event_type": "cash.movement.completed",
  "channel": "branch",
  "reference_id": "100",
  "amount_minor_units": 100000,
  "currency": "USD"
}
```
