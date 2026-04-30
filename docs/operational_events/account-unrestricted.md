# `account.unrestricted`

## Summary

Records that Branch servicing released an active Accounts-owned restriction by explicit forward action.

## Registry

| Field | Value |
| --- | --- |
| **`event_type`** | `account.unrestricted` |
| **Category** | Account control |
| **Lifecycle** | `posted_immediately` |
| **Allowed channels** | `branch` |
| **Financial impact** | `no_gl` |
| **Customer visible** | No |
| **Statement visible** | No |
| **Payload schema** | `docs/operational_events/account-unrestricted.md` |
| **Support search keys** | `source_account_id`, `reference_id`, `actor_id` |
| **Record command** | `Accounts::Commands::UnrestrictAccount` |

## Semantics

The event ends account-control effect for the referenced `account_restrictions` row. It does not post GL and is not a posting reversal.

## References

- [ADR-0036: Branch servicing event and audit taxonomy](../adr/0036-branch-servicing-event-audit-taxonomy.md)
