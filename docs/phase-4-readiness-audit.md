# Phase 4 readiness audit

**Status:** Draft  
**Last reviewed:** 2026-04-25  
**Companion docs:** [roadmap](roadmap.md), [deferred completion guide](roadmap-deferred-completion.md)

This audit checks whether BankCORE is ready to start Phase 4 channel work without bypassing the accounting kernel or carrying stale Phase 0-3 assumptions into external integrations.

Phase 4 should not begin by building every channel at once. It should begin with one vertical slice backed by an ADR, an integration test, and explicit mappings to `Core::OperationalEvents`, `Core::Posting`, `Core::Ledger`, and `Core::BusinessDate`.

## 1. Recommendation

**Go, with blockers before the first money-moving channel.**

The financial kernel is ready enough to design Phase 4: operational events are durable and idempotent, posting is centralized, journals are balanced through `PostEvent`, business-date close exists, and Phase 2/3 narrow slices provide product, fee, interest, overdraft, hold, statement, observability, and internal workspace foundations.

Do not implement ACH, wires, card settlement, partner writes, or fintech money movement until the first Phase 4 ADR is accepted. The ADR must define event taxonomy, channel identity, idempotency, settlement GL, cutoffs/business-date behavior, returns or reversals, reconciliation, and support visibility.

The safest first Phase 4 slice is **CSR / servicing read APIs over existing state**, because it can reuse current event, account, product, statement, and ledger reads without adding a new external money movement pathway. The safest first money-moving Phase 4 slice is **ACH receipt ingestion for a narrow credit/debit file path**, but only after the ACH ADR defines file/item idempotency, settlement accounts, returns, and EOD behavior.

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

- `Core::OperationalEvents::Commands::RecordEvent` accepts only configured channels (`teller`, `api`, `batch`, `system`) and supported financial event types.
- Idempotency is scoped to `(channel, idempotency_key)`, with request fingerprint checks to reject mismatched replays.
- `RecordEvent` asserts the event business date is the current open posting day.
- `Core::Posting::Commands::PostEvent` is the only GL write path for GL-backed operational events.
- `PostEvent` resolves posting legs through `Core::Posting::PostingRules::Registry`, validates balanced legs, creates posting batches, journal entries, and journal lines, then marks the event posted.
- `Core::OperationalEvents::Commands::RecordReversal` creates `posting.reversal` events for the reversible allowlist and blocks unsafe cases such as reversing a deposit with active linked holds or reversing an accrual after linked payout.
- `Core::OperationalEvents::EventCatalog` exposes client-facing metadata and must remain aligned with the posting registry for all GL-backed event types.

Phase 4 must preserve these invariants:

- External channels may record durable intent, but they must not write journal entries or journal lines directly.
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
- Phase 4 must introduce separate identity assumptions for external systems, partners, fintech apps, and customer channels. Do not reuse internal staff browser sessions or teller headers for those clients.
- Partner/customer APIs need response redaction rules, audit attribution, rate limits, idempotency expectations, and replay behavior before implementation.

Observability and support:

- `GET /teller/operational_events` and `ops/operational_events` provide bounded operational event search with posting/journal traceability.
- Full-text, branch-aware, and high-volume indexes remain deferred.
- Before high-volume ACH/card ingestion, define operational search needs for file id, batch id, item id, partner id, return code, settlement date, and customer account.
- Internal HTML workspaces exist, but request/system coverage for `internal`, `branch`, `ops`, and `admin` routes appears lighter than JSON teller coverage. If ops screens become required for Phase 4 support, add request or system tests for the critical screens.

Statements and customer-safe reads:

- Statement snapshots exist, but ADR-0024 explicitly excludes teller/customer HTTP routes, PDF rendering, delivery preferences, and document storage.
- CSR/customer API work can start with read-only account history and statement metadata if it defines redaction and authorization boundaries.
- Customer-facing statement delivery should remain a later slice unless Phase 4 explicitly chooses it as the first channel.

## 6. Readiness Backlog

Blockers before the first money-moving Phase 4 slice:

- Write and accept the first Phase 4 money movement ADR.
- Reconcile `docs/roadmap-deferred-completion.md` with current shipped Phase 2/3 narrow slices.
- Update `docs/roadmap.md` stale event-catalog and near-term checkpoint language.
- Define channel identity and idempotency rules beyond staff/teller operators.
- Define settlement GL and reversal/return policy for the selected channel.
- Add operational event specs for any new Phase 4 `event_type` values.

Should fix before the first channel ships:

- Add drift checks or documentation checks that cover `EventCatalog`, `PostingRules::Registry`, and `docs/operational_events/`.
- Add request/system coverage for the internal ops screens required to support the first channel.
- Define support search fields for channel file/batch/item identifiers.
- Clarify ADR-0019 wording now that interest and NSF slices exist.
- Fix ADR-0001's stale module-catalog path and explain that its migration phase labels are not roadmap phase labels.

Later Phase 4 follow-ups:

- Full product resolver depth and per-product GL mapping.
- Full-text and branch-aware event search.
- Multi-branch or multi-entity business-date and GL dimensions.
- Materialized reporting snapshots and drift checks for higher volume.
- Customer document delivery, statement PDFs, notifications, and delivery preferences.
- Full allowed-overdraft, representment, card dispute, and returned-item lifecycles.

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

Choose one of these as the next milestone:

- **Preferred readiness slice:** CSR / servicing read API over existing operational events, account summary, product summary, and generated statement metadata. This validates external contract shape, redaction, auth assumptions, and observability without introducing a new posting pathway.
- **Preferred money movement slice:** ACH receipt ingestion for one narrow deposit-credit path. The slice should parse a minimal inbound file representation, assign stable file/item ids, record a new operational event, post through the registry, expose support search by item id, and prove balanced journals in one integration test.

Do not start with wires or card settlement unless the product goal specifically requires dual control, authorization holds, dispute handling, or settlement matching as the first Phase 4 story.

