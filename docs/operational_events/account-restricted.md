# `account.restricted`

## Summary

Records that Branch servicing applied an Accounts-owned restriction or freeze to a deposit account.

## Registry

| Field | Value |
| --- | --- |
| **`event_type`** | `account.restricted` |
| **Category** | Account control |
| **Lifecycle** | `posted_immediately` |
| **Allowed channels** | `branch` |
| **Financial impact** | `no_gl` |
| **Customer visible** | No |
| **Statement visible** | No |
| **Payload schema** | `docs/operational_events/account-restricted.md` |
| **Support search keys** | `source_account_id`, `reference_id`, `actor_id` |
| **Record command** | `Accounts::Commands::RestrictAccount` |

## Semantics

The event is evidence of account-control state. It does not post GL and must be backed by an `account_restrictions` row.

## References

- [ADR-0036: Branch servicing event and audit taxonomy](../adr/0036-branch-servicing-event-audit-taxonomy.md)
