# Title (`event_type.string.here`)

> Copy this file to a new kebab-case name (e.g. `fee-assessed.md` for `fee.assessed`). Replace all placeholders. Remove this block quote when done.

## Summary

(One short paragraph.)

## Registry

| Field | Value |
| ----- | ----- |
| **`event_type`** | `…` |
| **Category** | Financial \| Servicing \| Operational |
| **Phase** | Draft \| Phase 1 \| … |
| **Lifecycle** | `pending_to_posted` \| `posted_immediately` |
| **Allowed channels** | `teller`, `branch`, `api`, `batch`, `system` as applicable |
| **Financial impact** | `gl_posting` \| `optional_gl` \| `no_gl` |
| **Customer visible** | Yes \| No |
| **Statement visible** | Yes \| No |
| **Payload schema** | `docs/operational_events/<this-file>.md` |
| **Support search keys** | `source_account_id`, `reference_id`, `actor_id`, etc. |

## Semantics

(Bullets: preconditions, postconditions, must-never rules.)

## Persistence

| Column / concept | Required | Notes |
| ---------------- | -------- | ----- |
| `event_type` | Yes | |
| … | … | |

## Lifecycle

(`pending` → `posted`, or single-step; note meaning for non-GL types.)

## Posting

(Yes/No; if yes, leg sketch and subledger notes.)

## Idempotency

(Scope `(channel, idempotency_key)`; fingerprint fields.)

## Reversals

(GL reversal pattern or N/A; link to [compensating-reversal.md](compensating-reversal.md) if applicable.)

## Relationships

(Sessions, accounts, holds, FKs.)

## Module ownership

(Which `app/domains/**` owns commands.)

## References

- [ADR-0002](../adr/0002-operational-event-model.md)

## Examples

(JSON or narrative.)
