I’ll draft this as a BankCORE-shaped phased roadmap, separating branch-safe MVP from later full-core capabilities and naming module ownership, events, controls, and deferred decisions.## BankCORE Phased Branch Operations Plan

### Phase 0: Canonical Capability Map
Create a docs artifact that maps branch activity to BankCORE modules and ADR coverage.

Scope:
- Define each branch activity as `MVP`, `near-term`, or `post-MVP`.
- Map activities to owners: `Party`, `Accounts`, `Products`, `Teller`, `Cash`, `Workspace`, `Organization`, `Workflow`, `Integration`, `Core::*`.
- For each activity, name whether it creates an operational event, a posting, a read model, or only reference data.

Key rule: this is a planning/catalog pass only. No new money movement semantics.

### Phase 1: Branch-Safe MVP Core
Goal: a branch can open accounts, move money safely, balance teller work, and close the day.

Included:
- Customer and basic account lifecycle: CIF creation, deposit account opening, basic account profile.
- Teller transactions: deposits, withdrawals, transfers, fees, holds, reversals.
- Teller sessions: open/close drawer, expected vs actual cash, variance approval.
- Core ledger: balanced posting, trial balance, immutable journal history.
- EOD readiness: pending events, open sessions, trial balance checks.
- Staff identity and authority: operators, capabilities, supervisor gates.
- Operating-unit scope: `operating_unit_id` for branch/session/event attribution.

Owners:
- `Party`: customer records.
- `Accounts`: deposit accounts, holds, available-balance support.
- `Teller`: teller sessions and workstation workflows.
- `Core::OperationalEvents`: durable intent and audit facts.
- `Core::Posting` / `Core::Ledger`: financial truth.
- `Workspace` / `Organization`: actor and branch scope.

Already aligned with current BankCORE direction.

### Phase 2: Cash Custody and Branch Controls
Goal: move from drawer-session cash control to true branch cash inventory.

Included:
- `cash_locations`: branch vaults, teller drawers, internal transit.
- `cash_movements`: vault-to-drawer, drawer-to-vault, internal transfers.
- `cash_counts`, `cash_variances`, rebuildable `cash_balances`.
- Dual-control hooks for vault movements.
- Cash position and reconciliation queries.

Candidate events:
- `cash.movement.completed`
- `cash.count.recorded`
- `cash.variance.posted`

Owners:
- `Cash`: locations, movements, counts, custody balances.
- `Teller`: session lifecycle only.
- `Core::Posting`: only for GL-impacting variance or external cash events.

Deferred:
- Fed/correspondent shipments.
- ATM cash.
- denomination tracking.
- branch-level GL.

### Phase 3: Branch Servicing Depth
Goal: make CSR/platform work complete enough for daily servicing.

Included:
- Account maintenance: signer maintenance, restrictions, status changes.
- Customer profile maintenance.
- Statement/history review.
- Fee waivers, hold release, reversals through Branch workspace.
- Durable audit for servicing changes.

Candidate events/audit records:
- `account.restricted`
- `account.unrestricted`
- `account.closed`
- `party.contact.updated`
- Account-party maintenance audit rows.

Owners:
- `Accounts`: account state and relationships.
- `Party`: customer identity/contact data.
- `Branch` controllers: workspace orchestration only.
- `Workflow`: durable approvals once maker-checker is generalized.

Deferred:
- full KYC/CIP automation.
- document retention workflows.
- customer self-service.

### Phase 4: Product Behavior Engine
Goal: stop hardcoding behavior and make account/product decisions reproducible.

Included:
- Product contract snapshots.
- Deposit product behavior resolver.
- Rules engine for limits, fees, holds, overdraft, interest, statement behavior.
- Rule trace/audit linkage to operational events or servicing records.

Owners:
- `Products`: product configuration.
- `Deposits`: product-driven servicing decisions.
- `Accounts`: account state.
- `Core::*`: posting and ledger unchanged.

Deferred:
- per-product GL mapping until a dedicated posting slice.
- full CD/time-deposit lifecycle unless selected as a vertical slice.

### Phase 5: Negotiable Instruments
Goal: support check cashing and official checks without overloading Teller.

Recommended first slice:
- Account-funded official check issuance.

Candidate event:
- `official_check.issued`

Likely posting:
- Dr `2110` customer DDA
- Cr `2160` Official Checks Outstanding

Owners:
- New or explicit domain decision needed, likely `Instruments` or `Payments::Instruments`.
- `Teller`: workstation initiation.
- `Core::Posting`: posting rules.
- `Cash`: only if cash-funded.

Later:
- cash-funded official checks.
- on-us check cashing.
- transit check cashing.
- void, stop, paid, returned, replacement lifecycle.
- reconciliation and positive pay.

This needs an ADR before implementation.

### Phase 6: External Payments and Rails
Goal: connect BankCORE to external movement while preserving the same event/posting kernel.

Included:
- ACH read/write maturity.
- Wires.
- card/ATM settlement.
- returned items and exceptions.
- file/batch lifecycle tracking.

Owners:
- `Integration`: rail adapters and ingestion/origination.
- `Core::OperationalEvents`: canonical facts.
- `Core::Posting`: settlement/accounting.
- `Accounts`: account validation and available funds.

Deferred:
- real-time rails scale concerns.
- full NACHA parsing beyond accepted slices.
- disputes/provisional credit unless separately scoped.

### Phase 7: Compliance, Risk, Reporting, and Scale
Goal: production-grade oversight and regulatory operations.

Included:
- AML/CTR/sanctions workflows.
- compliance cases and evidence.
- operational dashboards.
- reporting snapshots.
- branch-aware event filters and support tools.
- eventually multi-branch or multi-entity accounting.

Owners:
- `Compliance`: cases, alerts, evidence.
- `Reporting`: projections/extracts.
- `Documents`: retained artifacts.
- `Core::Ledger`: financial reporting truth.

Deferred until explicit ADR:
- branch-scoped business dates.
- branch GL segments.
- multi-entity consolidation.
- interbranch settlement.

## MVP Boundary
For MVP, keep the target as:

- Customers/accounts can be created.
- Deposits, withdrawals, transfers, fees, holds, and reversals post correctly.
- Teller sessions and branch scope are auditable.
- Books balance through trial balance.
- EOD readiness can prove unresolved work.
- Cash drawer control exists, even if full vault/cash inventory comes next.

Everything else should be phased only when it strengthens financial correctness, auditability, or the selected branch operating story.