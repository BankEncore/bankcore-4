# ADR-0036: Branch servicing event and audit taxonomy

## Status

Accepted

## Date

2026-04-29

## Context

Phase 3 Branch Servicing Depth adds account and party maintenance beyond the shipped Branch CSR foundation from ADR-0026. The planned work includes account restrictions, account lifecycle changes, broader account-party servicing, and party contact maintenance.

BankCORE already has two durable evidence patterns:

- `Core::OperationalEvents` for durable business facts that support posting, reversal linkage, operational search, and cross-domain audit context.
- Domain-owned audit rows for module-local maintenance history, such as `deposit_account_party_maintenance_audits`.

Phase 3 needs a clear rule so Branch servicing does not turn operational events into a generic row-change log, while still making account-control state changes searchable alongside financial and servicing activity.

## Decision

BankCORE will use operational events for Branch servicing actions that change account behavior in a way support, audit, or transaction authorization needs to search alongside financial activity.

BankCORE will use domain-owned audit rows for reference, relationship, and customer-profile maintenance that does not directly change posting, balance, or transaction-authorization behavior.

Initial taxonomy:

| Servicing action | Evidence type | Owner | Notes |
| --- | --- | --- | --- |
| Restrict account | No-GL operational event: `account.restricted` | `Accounts`, `Core::OperationalEvents` | Affects account behavior and support timeline. |
| Remove restriction | No-GL operational event: `account.unrestricted` | `Accounts`, `Core::OperationalEvents` | Reverses/ends account-control state by forward action. |
| Close account | No-GL operational event: `account.closed` | `Accounts`, `Core::OperationalEvents` | Major account lifecycle fact; does not post GL by itself. |
| Authorized-signer add/end | Domain audit row | `Accounts` | Existing `deposit_account_party_maintenance_audits`; do not duplicate as operational events. |
| Other non-financial account-party maintenance | Domain audit row | `Accounts` | Requires separate design if legal ownership semantics change. |
| Party contact maintenance | Domain audit row | `Party` | Initial contact updates do not affect posting or debit authorization. |

Operational events selected by this ADR are no-GL events unless a future ADR explicitly introduces a financial effect. They must not create journal entries and must not bypass `Accounts` command-layer rules.

### Account restriction taxonomy

Initial account restriction types:

```text
debit_block
full_freeze
close_block
watch_only
```

Deferred:

```text
credit_block
```

Restriction effects:

- `debit_block` blocks debit authorization paths such as withdrawals and outbound transfers.
- `full_freeze` blocks debit authorization and routine Branch servicing writes, except unrestrict/review actions.
- `close_block` blocks account close.
- `watch_only` is warning/evidence only and must not block transactions.

Do not add a separate `legal_hold` restriction type in this slice. Legal orders can be represented as `reason_code: legal_order` on `debit_block` or `full_freeze`; money-specific holds remain in `holds`.

### Command-layer effects

First-slice guards:

- `Accounts::Commands::AuthorizeDebit` blocks on active `debit_block` or `full_freeze`.
- `Accounts::Commands::CloseAccount` blocks on active `close_block`, `debit_block`, or `full_freeze`.
- Routine Branch servicing writes block on active `full_freeze`.
- Deposits and inbound credits remain allowed because `credit_block` is deferred.

Reversal and fee-waiver edge cases should not be over-wired beyond `full_freeze` guards in this slice. Direction-specific debit/credit behavior can be handled by a later targeted slice.

### Account close policy

`CloseAccount` may proceed only when:

- account status is `open`
- ledger and available balance are zero
- no active holds exist
- no pending operational events exist for the account
- no active `close_block`, `debit_block`, or `full_freeze` exists
- current business date is open
- actor has `account.maintain`
- idempotency replay matches the original request

Account close metadata belongs in an Accounts-owned lifecycle audit table, not as mutable history on `deposit_accounts`. `deposit_accounts.status` remains current state. The no-GL `account.closed` event links to the lifecycle row by `reference_id`.

Reopen is deferred. There is no `ReopenAccount` command, no `account.reopened` event, and no silent status flip from `closed` back to `open` in this slice.

### Party contact data shape

Party contact data uses typed Party-owned tables:

```text
party_emails
party_phones
party_addresses
party_contact_audits
```

Contact maintenance is append/supersede oriented. The first slice uses Party-owned audit rows rather than `party.contact.updated` operational events.

### Capabilities

Initial capability posture:

- Use existing `account.maintain` for account restrictions, account close, and account-party servicing.
- Add `party.contact.update` for Party contact maintenance.

Granular capabilities such as `account.restrict`, `account.close`, and `account_party.maintain` are deferred until access needs differ materially.

### Branch workspace and Workflow boundaries

Branch remains the internal servicing workspace. Do not introduce a separate `CustomerService` workspace in this slice.

Branch controllers normalize params, check navigation-level capabilities, call domain commands/queries, and render results. Commands enforce final authorization and business rules.

Generalized `Workflow` / maker-checker tables are deferred. Account restrictions, account close, account-party servicing, and Party contact updates are immediate command actions for authorized staff in this slice.

### Servicing timeline

Support evidence is composed read-side data, not a single write model. Account and Party profile pages may compose:

- operational events such as `account.restricted`, `account.unrestricted`, `account.closed`, `hold.placed`, `hold.released`, `fee.waived`, and `posting.reversal`
- Accounts audit rows such as authorized-signer maintenance and account lifecycle rows
- Party contact audit rows

Timeline entries should be normalized for display with:

```text
occurred_on
source_type
source_id
action
actor_id
summary
metadata
```

## Rules

- Branch controllers remain workspace orchestration only. They must call owning domain commands and must not mutate account lifecycle or Party profile rows directly.
- Account-control operational events must include actor, channel `branch`, business date, account id, idempotency key, reason, and enough reference data to support deterministic replay.
- Domain audit rows must include actor, channel or source surface, business date where relevant, subject id, action, old/new or effective values, and idempotency key when commands are retryable.
- Corrections are explicit forward actions: unrestrict, supersede, close, reopen if separately accepted, or new audit rows. Do not silently edit historical evidence.
- Operational event search is not the universal Branch change log. Domain timelines may compose operational events and domain audit rows for account profile support views.
- Timelines must not become the operational write model. Each domain continues to own its records.

## Consequences

Positive:

- Account-control changes are visible in the same operational evidence stream as other account-affecting activity.
- Party/contact and account-party maintenance stay owned by their domains without duplicating evidence.
- Phase 3 can add transaction guards for restrictions without introducing GL posting.

Negative:

- Account support timelines must compose multiple evidence sources.
- Implementers must decide, per new servicing action, whether behavior changes justify an operational event.

Neutral:

- Existing authorized-signer audit behavior remains valid.
- Existing Branch hold, fee waiver, and reversal flows keep their current operational-event behavior from ADR-0026.

## Deferred

- Universal customer/servicing timeline projection.
- Full KYC/CIP audit model.
- Document retention workflows.
- Customer self-service or external API contact maintenance.
- Generalized Workflow approval tables.
- Account reopen taxonomy, unless accepted by a later account lifecycle ADR.

## References

- [ADR-0002: Operational event model](0002-operational-event-model.md)
- [ADR-0026: Branch-hosted CSR servicing](0026-branch-csr-servicing.md)
- [ADR-0029: Capability-first authorization layer](0029-capability-first-authorization-layer.md)
- [BankCORE branch operations roadmap](../roadmap-branch-operations.md)
- [BankCORE module catalog](../architecture/bankcore-module-catalog.md)
