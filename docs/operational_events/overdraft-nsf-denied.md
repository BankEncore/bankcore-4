# Overdraft NSF denied (`overdraft.nsf_denied`)

## Summary

Records that an attempted withdrawal or transfer was denied because available balance was insufficient under the product overdraft policy. This is an operational audit event and does not post GL.

## Registry

| Field | Value |
| ----- | ----- |
| **`event_type`** | `overdraft.nsf_denied` |
| **Category** | Operational |
| **Phase** | P3-4 first vertical slice ([ADR-0023](../adr/0023-overdraft-nsf-deny-and-fee.md)). |
| **Lifecycle** | `posted_immediately` |
| **Allowed channels** | `teller`, `api`, `batch` |
| **Financial impact** | `no_gl` |
| **Customer visible** | Yes |
| **Statement visible** | Yes |
| **Payload schema** | `docs/operational_events/overdraft-nsf-denied.md` |
| **Support search keys** | `source_account_id`, `destination_account_id`, `reference_id`, `actor_id` |

## Semantics

- **Must** reference the attempted debit account via `source_account_id`.
- **Must** carry attempted `amount_minor_units` and `currency`.
- `destination_account_id` is present for denied `transfer.completed` attempts.
- `reference_id` records attempted type: `attempt:withdrawal.posted` or `attempt:transfer.completed`.
- No withdrawal or transfer financial event is created for the denied attempt.

## Persistence

| Column / concept | Required | Notes |
| ---------------- | -------- | ----- |
| `amount_minor_units`, `currency` | Yes | Attempted debit amount. |
| `source_account_id` | Yes | Account with insufficient available balance. |
| `destination_account_id` | Transfer only | Intended destination for denied transfer. |
| `reference_id` | Yes | Attempted type marker. |

## Lifecycle

Created directly in **`posted`** status; no `PostEvent` path.

## Posting

None.

## Idempotency

Fingerprint includes event type, channel, idempotency key, attempted amount/currency, source/destination account ids, `reference_id`, and actor.

## Reversals

Not reversed via `posting.reversal`; remediation is operational documentation and, if needed, waiving the linked NSF fee via `fee.waived`.

## Relationships

An NSF fee, when assessed, is a posted `fee.assessed` with `reference_id = "nsf_denial:<this event id>"`.

## Module ownership

`Accounts::Commands::AuthorizeDebit`, `Core::OperationalEvents::Commands::RecordControlEvent`.

## References

- [ADR-0023](../adr/0023-overdraft-nsf-deny-and-fee.md)
- [fee-assessed.md](fee-assessed.md)
