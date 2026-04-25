# BankCORE deferred roadmap completion guide

**Status:** Draft  
**Companion to:** [roadmap.md](roadmap.md)  
**Last reviewed:** 2026-04-24

This document describes what it would take to complete the items deferred by the current roadmap. It does not redefine the MVP boundary: [MVP vs Full System](concepts/01-mvp-vs-core.md), the [module catalog](architecture/bankcore-module-catalog.md), and accepted ADRs remain authoritative.

Use this as a backlog-shaping document. Each section is intentionally framed as completion work after the shipped narrow slices in [roadmap.md](roadmap.md), not as one large implementation request.

---

## 1. Completion Principles

Before expanding any deferred area:

- Keep financial truth in `Core::OperationalEvents`, `Core::Posting`, and `Core::Ledger`.
- Prefer a small vertical slice with one integration proof over a broad horizontal platform change.
- Add or update an ADR when posting rules, reversal rules, GL ownership, product behavior, or external integrations change.
- Treat product behavior as configuration resolved through `Products`; do not infer behavior from `product_code` alone.
- Preserve immutable history: corrections are new events, reversals, generated snapshots, or superseding rows, not silent edits.

---

## 2. Cross-Cutting Prerequisites

These capabilities will make multiple deferred tracks easier to complete.

### 2.1 Product Resolver Depth

Current state: `deposit_products` exists, and Phase 3 added fee, overdraft, and statement configuration tables. Full ADR-0005-style behavior profiles are still partial.

To complete:

- Define stable resolver contracts for product behavior: interest, fees, overdraft, statement cycles, limits, and GL mapping.
- Decide whether profiles are directly product-owned tables, reusable profile tables, or a hybrid.
- Add effective-dated conflict rules so only one active behavior applies for a product/date where exclusivity is required.
- Move remaining hardcoded behavior to resolver-backed decisions only when the resolver has tests and clear fallback semantics.

Likely slices:

- Product resolver contract ADR.
- Shared effective-dated resolver helpers under `Products`.
- Per-product GL mapping profile for existing event types.
- Migration path from current narrow rule tables to reusable profiles, if needed.

### 2.2 Reporting and Snapshot Strategy

Current state: balances are compute-on-read from journals, with generated statements now snapshotting their rendered line items.

To complete:

- Decide which projections need materialization: daily ledger balance, available balance, statement balances, branch totals, or regulatory extracts.
- Define invalidation/rebuild rules before adding any materialized balance table.
- Add reconciliation tests between projections and journal truth.

Likely slices:

- Daily balance snapshot ADR.
- `Reporting`-owned `daily_balance_snapshots` for GL 2110 by account/date.
- Rebuild command and drift check query.

### 2.3 Multi-Branch and Multi-Entity Foundations

Current state: the system assumes a singleton business date and a simple institution ledger.

To complete:

- Introduce branch/location identity where operational activity occurs.
- Decide business-date scope: institution-wide, branch-specific, or entity-specific.
- Extend GL and reporting dimensions without breaking existing posted history.
- Define consolidation rules before adding multi-entity accounting.

Likely slices:

- Branch/location data model and operator assignment.
- Branch-scoped teller session and cash location model.
- Branch-aware business date reads before branch-aware posting.
- Multi-entity GL ADR only after branch scoping is stable.

---

## 3. Phase 2 Deferred Completion

### 3.1 Ownership and Account Parties

Shipped narrow slice: two-party joint at account open.

To complete:

- Support additional participation roles beyond owner/joint owner, such as signer, custodian, beneficiary, and authorized user.
- Add post-open add/remove/supersede workflows with effective dating.
- Define signature authority and account access rules for each role.
- Add audit events for ownership and authority changes.
- Expose teller or servicing APIs for party maintenance.

Likely slices:

- ADR update for role taxonomy and authority semantics.
- `Accounts::Commands::AddAccountParty` and `EndAccountParty`.
- Servicing read model for current and historical parties.
- Teller/CSR integration tests for post-open ownership changes.

### 3.2 Full Product Configuration

Shipped narrow slice: `deposit_products` FK and product-aware reads.

To complete:

- Implement ADR-0005 resolver contracts across product behavior.
- Add reusable profiles or rule tables for interest, fees, limits, overdraft, statements, and GL mapping.
- Define product versioning: when a product change affects new accounts only versus existing accounts.
- Add admin/ops workflows for activating, retiring, and validating products.

Likely slices:

- Product resolver ADR and shared resolver conventions.
- Product version/effective-dating constraints.
- Product validation command that verifies all required active profiles.
- Per-product GL mapping for existing deposit event types.

### 3.3 Event Catalog Depth

Shipped narrow slice: code-first `EventCatalog`, event type discovery, and drift tests.

Phase 3 already added interest and NSF event entries, but deeper catalog completion remains open.

To complete:

- Define event lifecycle metadata consistently: reversible, compensating-only, no-GL, system-only, teller-session-required, and statement-visible.
- Add payload schema metadata for each event type.
- Add API discovery fields that distinguish operational, financial, servicing, and control events.
- Add catalog checks for documentation coverage and statement visibility rules.

Likely slices:

- Event catalog metadata expansion ADR.
- Catalog-driven validation docs and tests.
- Event docs drift check against catalog entries.
- Catalog fields for statement-visible and customer-visible behavior.

### 3.4 Operational Event Observability

Shipped narrow slice: bounded teller `GET /teller/operational_events`.

To complete:

- Add full-text search over event type, account number, reference id, and actor.
- Add branch-aware and multi-operator filters once branch identity exists.
- Decide customer-safe redaction rules versus teller/ops visibility.
- Add cursor pagination over compound ordering if IDs alone are not sufficient at volume.

Likely slices:

- Search index migration and query tests.
- Role-aware response shaping.
- Branch filter after branch model lands.
- Performance benchmark fixture for larger event volumes.

### 3.5 Business Date Close

Shipped narrow slice: singleton close after readiness checks and open-day posting invariant.

To complete:

- Define branch or entity scope for business dates.
- Add close checkpoints: teller sessions, unposted events, trial balance readiness, unresolved exceptions, and generated extracts.
- Define day reopen policy, including who can reopen and what data remains immutable.
- Add close reports and auditable close packages.

Likely slices:

- ADR for branch-scoped business date.
- Close checkpoint registry.
- Read-only close package generation.
- Reopen command with strict guardrails, if product accepts reopen at all.

### 3.6 Drawer Variance and Cash Operations

Shipped narrow slice: optional GL posting for teller drawer variance.

To complete:

- Model cash locations, vaults, teller drawers, and cash transfers.
- Add denomination-level cash counts where needed.
- Distinguish teller drawer GL, vault cash GL, and in-transit cash GL if product requires it.
- Add approvals for vault transfers and large cash movements.

Likely slices:

- `Cash` domain table ownership ADR.
- Vault and drawer location model.
- Cash transfer operational events and posting rules.
- Denomination count capture and reconciliation tests.

---

## 4. Phase 3 Deferred Completion

### 4.1 Interest Engine

Shipped narrow slice: explicit `interest.accrued` and `interest.posted` events with minor-unit posting.

To complete:

- Add product-owned interest rules: rate type, rate source, day count, compounding, accrual frequency, and payout frequency.
- Add a high-precision accumulator for sub-minor/microcent accrual.
- Define rounding rules at posting boundaries and how residuals carry forward.
- Add scheduled accrual and payout commands.
- Add reversal/correction workflows for generated interest.

Likely slices:

- Interest profile and microcent accumulator ADR.
- `Products` interest profile/rule schema and resolver.
- `Deposits::Commands::AccrueInterest` writing accumulator rows and emitting rounded `interest.accrued`.
- `Deposits::Commands::PostInterest` linking payouts to accruals.
- Reconciliation tests proving accumulator totals, rounded postings, and residual carry-forward.

### 4.2 Fee Engine

Shipped narrow slice: monthly maintenance fee engine.

To complete:

- Expand fee catalog beyond monthly maintenance: overdraft, statement copy, stop payment, wire, account research, dormant account, and transaction count fees.
- Add waiver/condition rules such as minimum balance, relationship balance, age/student/senior profile, and product campaign.
- Add schedules beyond one monthly run: per-event, daily, monthly, annual, and one-time fees.
- Add fee simulation/dry-run for ops review before posting.

Likely slices:

- Fee profile ADR and catalog.
- Fee condition evaluator.
- Event-triggered fee command.
- Fee assessment preview report.
- Fee waiver policy rules beyond manual `fee.waived`.

### 4.3 Holds Depth

Shipped narrow slice: deposit-linked holds and reversal guard.

To complete:

- Add hold expiration with due-hold processing.
- Add partial release or adjustment semantics.
- Define Reg CC / collected-funds schedules if deposit availability is product-controlled.
- Distinguish administrative holds, deposit holds, legal holds, and channel authorization holds.
- Add customer-visible hold history and available-balance explanations.

Likely slices:

- `expires_at` / `expires_on` schema and `ExpireDueHolds` command.
- Partial hold release ADR and event type.
- Hold reason/type taxonomy.
- Product-driven availability schedule resolver.
- Statement/history inclusion rules for hold lifecycle events.

### 4.4 Overdraft and NSF

Shipped narrow slice: deny NSF with forced fee.

To complete:

- Add allowed overdraft limits and available-balance authorization rules.
- Add eligibility and opt-in/opt-out rules, including consumer protection requirements if applicable.
- Model representment and returned-item lifecycle.
- Add separate OD/NSF fee policies if GL or disclosures differ.
- Add operational queues for exception handling and manual decisions.

Likely slices:

- Overdraft limit profile and authorization decision ADR.
- `Limits`-owned authorization decision persistence, if durable decisions are needed.
- Allow-overdraft posting path with explicit limit tracking.
- Representment event model.
- Fee/disclosure split for OD versus NSF.

### 4.5 Customer-Visible History and Statements

Shipped narrow slice: generated statement snapshots from GL 2110 and selected no-GL events.

To complete:

- Add customer and teller/CSR HTTP surfaces for account history and generated statements.
- Add document rendering, storage, and delivery preferences.
- Add statement corrections or regeneration policy for late postings, if allowed.
- Add statement fees and copy requests if product requires them.
- Add performance strategy for high-volume accounts.

Likely slices:

- Teller/CSR statement read endpoint.
- Customer-safe history endpoint with redaction and auth assumptions.
- `Documents` integration for rendered statement artifacts.
- Delivery preference model and generated notice events.
- Reporting snapshots or query optimization for high-volume accounts.

---

## 5. Phase 3.5 Internal UI Completion

Phase 3.5 is internal UI enablement over shipped Phase 0-3 domain capabilities. It is separate from Phase 4 customer/partner channels because it uses staff operators, internal role gates, and Rails-rendered branch/ops/admin workspaces. See [ADR-0025](adr/0025-internal-workspace-ui.md).

To complete:

- Add a shared internal Rails HTML shell with session-backed operator authentication.
- Add a `branch` workspace for branch-local teller session and transaction workflows.
- Add an `ops` workspace for EOD readiness, trial balance, operational event search/detail, close packages, and exception review.
- Add an `admin` workspace for product configuration inspection and later guarded configuration edits.
- Keep existing JSON `/teller` APIs stable for curl/tests/future clients.

Likely slices:

- WO2 shared shell/auth.
- WO3 branch session UI.
- WO4 ops EOD and event search UI.
- WO5 admin product read-only UI.
- WO6 branch transaction forms.
- WO7 guarded admin/ops control surfaces.

---

## 6. Phase 4 Completion Themes

Phase 4 is not merely a continuation of Phase 3. External channels introduce ingestion, settlement, returns, cutoffs, and reconciliation.

### 6.1 ACH

To complete:

- Add ACH file/batch ingestion with idempotent item identity.
- Separate origination, receipt, settlement, return, and reversal lifecycles.
- Define NACHA-specific validation and return code handling.
- Post only through operational events and posting rules.

First ADR should cover ACH event taxonomy, settlement accounts, file idempotency, and return handling.

### 6.2 Wires

To complete:

- Model wire instructions, approval workflow, cutoff, release, and settlement.
- Add domestic/international distinctions only when product scope requires them.
- Define GL settlement accounts and fee side effects.
- Add dual control and audit requirements.

First ADR should cover wire lifecycle, authorization gates, settlement posting, and cancellation/reversal policy.

### 6.3 Cards and ATM

To complete:

- Model authorization holds, clearing, settlement, reversals, and disputes.
- Add channel-specific available-balance rules.
- Integrate card/ATM settlement files without bypassing posting.
- Define dispute provisional credit workflows.

First ADR should cover auth versus clearing, hold expiration, settlement matching, and dispute event types.

### 6.4 CSR, Partner, and Fintech APIs

To complete:

- Add non-teller workspace controllers with explicit auth assumptions.
- Define customer-safe response contracts and redaction.
- Add rate limits, idempotency expectations, and audit attribution.
- Keep controllers as orchestrators over domain commands/queries.

First slices should expose existing domain reads before introducing new money movement.

---

## 7. Phase 5 Completion Themes

Phase 5 moves the system toward regulatory and scale readiness.

### 7.1 Compliance and Risk

To complete:

- AML monitoring rules and case queues.
- CTR workflow and reporting data capture.
- Sanctions screening for parties and transactions.
- Fraud signals and decisioning hooks.

First slices should be read/audit projections over existing immutable events before blocking transaction flows.

### 7.2 Regulatory and Finance Reporting

To complete:

- Regulatory extracts and filing-ready reports.
- Multi-entity consolidation reporting.
- Period close packages and finance attestations.
- Data warehouse or BI export patterns.

First slices should reconcile generated reports back to ledger and operational-event sources.

### 7.3 Scale and Operations

To complete:

- Partitioning or archival strategy for operational events and journals.
- Rebuildable projections for high-volume reads.
- Background job orchestration and retry semantics.
- Observability for posting failures, close failures, and projection drift.

First slices should add measurable performance targets and drift detection before optimizing storage shape.

---

## 8. Suggested Sequencing

Recommended order from current state:

1. Complete product resolver depth, because interest, fees, overdraft, statements, and GL mapping all depend on it.
2. Add hold expiration and partial release, because it improves available-balance clarity without external integrations.
3. Add interest engine accumulator and scheduled posting, because microcent precision is already an identified product need.
4. Add statement/customer history HTTP reads, because generated statements now exist and can be exposed without new posting behavior.
5. Add branch/cash-location foundations before multi-branch business date and multi-entity GL.
6. Add ACH only after event taxonomy, idempotency, settlement GL, and return handling are documented in an ADR.

This order keeps financial invariants close to already-shipped code while delaying broad channel and regulatory scope until the internal product model is stronger.
