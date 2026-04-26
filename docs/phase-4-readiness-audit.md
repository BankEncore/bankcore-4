# Phase 4 readiness audit

**Status:** Draft  
**Last reviewed:** 2026-04-25  
**Companion docs:** [roadmap](roadmap.md), [deferred completion guide](roadmap-deferred-completion.md)

This audit checks whether BankCORE is ready to continue Phase 4 channel work without bypassing the accounting kernel or carrying stale Phase 0-3 assumptions into external integrations.

Phase 4 should not begin by building every channel at once. It should begin with one vertical slice backed by an ADR, an integration test, and explicit mappings to `Core::OperationalEvents`, `Core::Posting`, `Core::Ledger`, and `Core::BusinessDate`.

## 1. Recommendation

**Go, with blockers before the first money-moving channel.**

The financial kernel is ready enough to design Phase 4: operational events are durable and idempotent, posting is centralized, journals are balanced through `PostEvent`, business-date close exists, and Phase 2/3 narrow slices provide product, fee, interest, overdraft, hold, statement, observability, and internal workspace foundations.

Do not implement ACH, wires, card settlement, partner writes, or fintech money movement until the first Phase 4 ADR is accepted. The ADR must define event taxonomy, channel identity, idempotency, settlement GL, cutoffs/business-date behavior, returns or reversals, reconciliation, and support visibility.

The first Phase 4 slice is now **Branch CSR servicing** ([ADR-0026](adr/0026-branch-csr-servicing.md)): internal staff customer/account servicing under the existing Branch HTML workspace. It reuses current party, account, product, statement, operational-event, and ledger-derived reads, and exposes guarded existing servicing actions without introducing a new external money movement pathway. The safest first money-moving Phase 4 slice remains **ACH receipt ingestion for a narrow credit/debit file path**, but only after the ACH ADR defines file/item idempotency, settlement accounts, returns, and EOD behavior.

## 2. Shipped State Inventory

Phase 0 and Phase 1 foundations are present:

- Hygiene items in `docs/roadmap.md` Phase 0 are marked done.
- Core teller flows for deposits, withdrawals, transfers, reversals, teller sessions, holds, trial balance, EOD readiness, and supervisor gates are covered by integration tests under `test/integration/`.
- `config/routes.rb` exposes the JSON `/teller` workspace and internal HTML `branch`, `ops`, and `admin` workspaces.

Phase 2 narrow slices are present:

- `deposit_products` and product-aware account context are documented in ADR-0017 and exposed through teller account creation and event listing.
- `EventCatalog` and `GET /teller/event_types` exist, with drift coverage against GL-backed posting handlers.
- `GET /teller/operational_events` supports bounded date filters, product filters, pagination, and posting/journal traceability through `Core::OperationalEvents::Queries::ListOperationalEvents`.
- Supervisor business-date close is implemented through `Core::BusinessDate::Commands::CloseBusinessDate`.
- Optional teller drawer variance posting is represented by `teller.drawer.variance.posted` when enabled.

Phase 3 narrow slices are present:

- Interest events `interest.accrued` and `interest.posted` post through the kernel with payout linkage and reversal guards.
- Monthly maintenance fee assessment uses product-owned fee rules, deterministic idempotency, and `fee.assessed`.
- Deposit-linked holds enforce same-account/currency limits and block reversal while active.
- Deny-NSF overdraft policy records no-GL `overdraft.nsf_denied` and posts a linked NSF `fee.assessed`.
- Deposit statement snapshots are generated in `Deposits` from posted GL 2110 journal lines plus selected no-GL servicing events.

Phase 3.5 internal workspace foundations are present:

- `branch`, `ops`, and `admin` HTML namespaces exist.
- Browser sessions authenticate staff operators through `Workspace::Models::Operator`.
- `ops` exposes EOD, business-date close, engine runs, teller variances, and operational event search/detail.
- `admin` exposes product and rule inspection plus guarded effective-dated rule changes.
- This is internal staff UI only; it must not be reused for customer, partner, or fintech authentication.

Phase 4.1 Branch CSR servicing is present:

- `branch` exposes customer search, customer 360, deposit-account profile, activity, holds, and statement metadata pages.
- Branch CSR reads are backed by domain queries under `Party`, `Accounts`, `Deposits`, and `Core::OperationalEvents`.
- Non-cash Branch servicing writes use operational-event channel `branch` and authenticated operator `actor_id`.
- Guarded actions include account hold placement/release, fee waiver, and posting reversal flows through existing commands and `Core::Posting`.

## 3. Documentation Drift

`docs/roadmap-deferred-completion.md` is the largest readiness risk because it still describes a Slice-1-only state in several sections:

- Product resolver depth says `deposit_products` and the `Products` domain are not shipped.
- Reporting says customer-visible statements and statement snapshots are not shipped.
- Event catalog depth says only `deposit.accepted` exists and no formal catalog, discovery API, or drift tests exist.
- Drawer variance says no teller sessions or cash variance model exists.
- Phase 3 sections say no interest, fee engine, holds, overdraft/NSF, or statement generation is shipped.
- Suggested sequencing still says the current state is single deposit, single owner, no Products/Holds/Sessions.

`docs/roadmap.md` is mostly current, but these lines should be cleaned up before Phase 4 planning depends on it:

- The Phase 2 event catalog row still lists interest and NSF events as deferred even though Phase 3 narrow slices now ship `interest.*` and `overdraft.nsf_denied`.
- The remaining gaps section says interest and NSF-style models are not shipped; it should distinguish shipped narrow event types from richer composite/product engines.
- The near-term recommendation points to sections 4 and 7 but omits Phase 3 section 8.
- The Phase 3 heading links to a user-local preliminary plan path; repo docs should not rely on that path as a durable source.

ADR-level drift is lower severity:

- ADR-0019 correctly remains the fee/catalog ADR, but its context says the Phase 2 roadmap calls for fees, interest, and NSF. Now that ADR-0021 through ADR-0023 exist, a wording pass should clarify that ADR-0019 introduced the first fee pair and the catalog later expanded.
- ADR-0001 uses its own migration phases and has a related-doc path of `docs/architecture/module-catalog.md`; the current catalog path is `docs/architecture/bankcore-module-catalog.md`. Phase 4 planning should avoid confusing ADR-0001 migration phase numbers with roadmap Phase 4.

## 4. Kernel Readiness

The core money path is suitable as a Phase 4 foundation:

- `Core::OperationalEvents::Commands::RecordEvent` accepts only configured channels (`teller`, `branch`, `api`, `batch`, `system`) and supported financial event types.
- Idempotency is scoped to `(channel, idempotency_key)`, with request fingerprint checks to reject mismatched replays.
- `RecordEvent` asserts the event business date is the current open posting day.
- `Core::Posting::Commands::PostEvent` is the only GL write path for GL-backed operational events.
- `PostEvent` resolves posting legs through `Core::Posting::PostingRules::Registry`, validates balanced legs, creates posting batches, journal entries, and journal lines, then marks the event posted.
- `Core::OperationalEvents::Commands::RecordReversal` creates `posting.reversal` events for the reversible allowlist and blocks unsafe cases such as reversing a deposit with active linked holds or reversing an accrual after linked payout.
- `Core::OperationalEvents::EventCatalog` exposes client-facing metadata and must remain aligned with the posting registry for all GL-backed event types.

Phase 4 must preserve these invariants:

- Internal Branch CSR and external channels may record durable intent, but they must not write journal entries or journal lines directly.
- New GL-backed `event_type` values require an `EventCatalog` entry, a posting rule handler, docs under `docs/operational_events/`, and an integration test proving record to post to balanced journal.
- No-GL servicing/control events must still define lifecycle, idempotency, visibility, and whether they can trigger compensating financial events.
- Returns, cancellations, corrections, and disputes must be modeled as new events or compensating events, not edits to posted rows.

## 5. Channel Dependency Audit

Business date and close:

- `CloseBusinessDate` advances the singleton business date only after EOD readiness passes.
- EOD readiness currently checks balanced journals, no open or pending-supervisor teller sessions, and no pending operational events for the date.
- Phase 4 ADRs must define how incoming files, cutoffs, settlement timing, and pending channel items affect close readiness.
- Multi-branch and multi-entity calendars remain deferred; if the first channel needs branch/entity-level settlement, that foundation becomes a blocker.

Product, balance, and GL mapping:

- Current product behavior covers deposit products, monthly maintenance fees, deny-NSF overdraft policy, and monthly statement profiles.
- Full ADR-0005 resolver depth and per-product GL mapping remain deferred.
- Phase 4 money movement must not infer behavior from `product_code` alone.
- ACH and card debit authorization must explicitly decide how available balance, holds, NSF/OD policy, and channel-specific limits interact.
- ACH/wire/card settlement accounts are not defined yet; each money-moving ADR must define the required GL accounts and posting rules.

Identity and authorization:

- JSON teller APIs use `X-Operator-Id` and database-backed operator roles.
- Internal HTML workspaces use session-backed staff operators.
- Branch CSR servicing uses the same internal staff browser session trust boundary as `branch`, with role gates on supervisor actions. It must not be reused as partner, fintech, or customer authentication.
- Phase 4 must introduce separate identity assumptions for external systems, partners, fintech apps, and customer channels. Do not reuse internal staff browser sessions or teller headers for those clients.
- Partner/customer APIs need response redaction rules, audit attribution, rate limits, idempotency expectations, and replay behavior before implementation.

Observability and support:

- `GET /teller/operational_events` and `ops/operational_events` provide bounded operational event search with posting/journal traceability.
- Full-text, branch-aware, and high-volume indexes remain deferred.
- Before high-volume ACH/card ingestion, define operational search needs for file id, batch id, item id, partner id, return code, settlement date, and customer account.
- Internal HTML workspaces exist, but request/system coverage for `internal`, `branch`, `ops`, and `admin` routes appears lighter than JSON teller coverage. If ops screens become required for Phase 4 support, add request or system tests for the critical screens.

Statements and customer-safe reads:

- Statement snapshots exist, and Branch CSR servicing now exposes internal staff statement metadata and account activity. ADR-0024 still excludes customer-facing PDF rendering, delivery preferences, and document storage.
- Customer API work can start with read-only account history and statement metadata only after it defines redaction and authorization boundaries separate from Branch staff UI.
- Customer-facing statement delivery should remain a later slice unless Phase 4 explicitly chooses it as the first channel.

## 6. Readiness Backlog

Backlog by revised Phase 4 slice:

- **4.2 Event Catalog and Channel Metadata:** add lifecycle/channel metadata, statement-visible and customer-visible flags, payload schema references, and drift checks that cover `Core::OperationalEvents::EventCatalog`, `Core::Posting::PostingRules::Registry`, and `docs/operational_events/`. Add operational-event specs for any new Phase 4 `event_type` values before implementation.
- **4.3 Product Resolver Baseline:** define resolver contracts and effective-dated helper conventions for product behavior that channel code must depend on. Include per-product GL mapping only if the selected money-moving channel needs it.
- **4.4 Servicing Depth:** shipped narrow Branch servicing depth: hold reason/type/expiration metadata and due expiration, current/historical account-party reads, and supervisor-only `authorized_signer` add/end workflows with audit evidence. Partial hold release/adjustment and post-open owner/joint-owner maintenance still need separate ADRs.
- **4.5 Support Observability and Close Readiness:** shipped narrow Ops readiness depth: operational-event support-key filters and indexes for reference/idempotency/reversal support search, plus read-only close-package EOD impact evidence by event status, channel, and type. Materialized balance snapshots and branch-scoped business dates remain deferred.
- **4.6 External Read APIs:** ADR-0027 and the external read API contract plan define the next implementation gate. Cover client identity, auth, redaction, rate limits, response contracts, idempotency expectations, and audit attribution. Start with reads over existing account, event, product, statement, and ledger-derived state; do not reuse Branch browser sessions or teller headers.
- **4.7 First Money-Moving Channel:** write and accept the ACH ADR before implementation. Define channel identity, file/item idempotency, event taxonomy, settlement GL, reversal/return policy, cutoffs/EOD blocking, support search, and reconciliation evidence.

Items to keep outside Phase 4 unless a selected channel requires them:

- Multi-branch or multi-entity business-date and GL dimensions.
- Materialized reporting snapshots beyond close evidence or measured read-performance needs.
- Customer document delivery, statement PDFs, notifications, and delivery preferences.
- Wires, cards/ATM, allowed overdraft, representment, disputes, and provisional-credit workflows.
- Full AML/CTR/sanctions/fraud workflows.

## 7. ADR Backlog

First ACH ADR:

- Define ACH event taxonomy for file receipt, batch acceptance, item posting, settlement, return, reversal, and rejection.
- Define idempotency at file, batch, and item levels.
- Define settlement GL accounts and whether customer posting happens at receipt, settlement, or both.
- Define NACHA validation and return-code handling.
- Define cutoff/business-date behavior and what blocks EOD close.
- Define reconciliation evidence from source file through operational events, posting batches, and journals.

First wire ADR:

- Define incoming/outgoing wire lifecycle, approval workflow, release, cancellation, and reversal policy.
- Define domestic/international scope for the first slice.
- Define dual control and audit attribution.
- Define settlement GL and fee side effects.
- Define cutoff behavior and ops exception handling.

First card/ATM ADR:

- Define authorization versus clearing versus settlement.
- Define authorization holds, expiration, and matching.
- Define available-balance rules and product/overdraft interaction.
- Define reversals, disputes, and provisional credit policy.
- Define settlement file ingestion without bypassing posting.

First external API ADR:

- Define client identity for CSR, partner, fintech, and customer surfaces.
- Define auth, redaction, rate limiting, and idempotency.
- Define audit attribution for system actors versus human operators.
- Start with read APIs over existing account, event, product, statement, and ledger-derived state.
- Require separate ADR review before external API writes create financial events.

## 8. First Slice Recommendation

The next milestone is **4.2 Event Catalog and Channel Metadata**.

Completed readiness slice: Branch CSR servicing over existing operational events, account summary, product summary, generated statement metadata, and guarded existing servicing actions. This validated internal staff contract shape, Branch auth assumptions, and audit attribution without introducing a new posting pathway.

Preferred first money movement after 4.2-4.6: ACH receipt ingestion for one narrow deposit-credit path. The slice should parse a minimal inbound file representation, assign stable file/item ids, record a new operational event, post through the registry, expose support search by item id, and prove balanced journals in one integration test.

Do not start with wires or card settlement unless the product goal specifically requires dual control, authorization holds, dispute handling, or settlement matching as the first Phase 4 story.

## 9. Phase 4.2 Slice Plan

Goal: make event semantics explicit enough that Branch CSR, statements/history, support search, external read APIs, and the first ACH slice do not each reinvent lifecycle and visibility rules.

Scope:

- Extend `Core::OperationalEvents::EventCatalog::Entry` with metadata for lifecycle, allowed channels, GL behavior, customer visibility, statement visibility, and payload schema/spec reference.
- Keep the catalog code-first for now; do not introduce database-backed event-type configuration in this slice.
- Add catalog helpers for channel-facing discovery so later external APIs can filter customer-safe and statement-visible events without hardcoding event-type lists.
- Strengthen drift tests so every catalog entry is documented, every GL-backed entry has a posting handler, every spec declares matching registry metadata, and every visibility flag has an explicit docs value.
- Update `docs/operational_events/README.md` and per-type specs to document the new metadata fields using the existing spec format.
- Add a short 4.2 implementation note or ADR only when the metadata shape is about to be implemented; do not create placeholder ADRs up front.

Initial metadata fields:

- `lifecycle`: for example `posted_immediately`, `control`, or future `pending_to_posted`.
- `allowed_channels`: for example `teller`, `branch`, `system`, and later external channel ids.
- `financial_impact`: `gl_posting`, `no_gl`, or `optional_gl`.
- `customer_visible`: whether this event can appear in customer-safe history after redaction.
- `statement_visible`: whether this event can appear in generated statement history.
- `payload_schema`: stable docs/schema reference for required payload shape.
- `support_search_keys`: references that support and ops should be able to search, such as account id, reference id, actor id, teller session id, or future file/batch/item ids.

Acceptance checks:

- `Core::OperationalEvents::EventCatalog.as_api_array` exposes the new metadata without breaking existing fields.
- Tests fail when a catalog entry omits visibility/channel/lifecycle metadata.
- Tests fail when operational-event docs drift from catalog GL posting, record command, visibility, or payload-schema references.
- Statement/customer visibility values are explicit for all shipped event types, including no-GL servicing/control events.
- ACH planning can cite catalog metadata requirements instead of creating separate event semantics tables.

Non-goals:

- No new external API endpoints.
- No ACH ingestion or new money-moving `event_type` values.
- No full product resolver, reporting snapshot, document delivery, or compliance workflow implementation.

