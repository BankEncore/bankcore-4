# `account.closed`

## Summary

Records that Branch servicing explicitly closed a deposit account after Accounts-owned lifecycle preconditions passed.

## Registry

| Field | Value |
| --- | --- |
| **`event_type`** | `account.closed` |
| **Category** | Account control |
| **Lifecycle** | `posted_immediately` |
| **Allowed channels** | `branch` |
| **Financial impact** | `no_gl` |
| **Customer visible** | No |
| **Statement visible** | No |
| **Payload schema** | `docs/operational_events/account-closed.md` |
| **Support search keys** | `source_account_id`, `reference_id`, `actor_id` |
| **Record command** | `Accounts::Commands::CloseAccount` |

## Semantics

The event is durable lifecycle evidence linked to an `account_lifecycle_events` row. It does not post GL; account balance payout, if needed, must be handled before close through separate financial paths.

## References

- [ADR-0036: Branch servicing event and audit taxonomy](../adr/0036-branch-servicing-event-audit-taxonomy.md)
