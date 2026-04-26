# BankCORE development roadmap

**Status:** Draft  
**Last reviewed:** 2026-04-27  

This document **sequences** engineering work. It does **not** redefine scope: MVP boundaries stay in [docs/concepts/01-mvp-vs-core.md](concepts/01-mvp-vs-core.md); boundaries and ownership stay in [docs/architecture/bankcore-module-catalog.md](architecture/bankcore-module-catalog.md) and the ADRs under [docs/adr/](adr/).

For completion planning on the deferred items called out below, see [roadmap-deferred-completion.md](roadmap-deferred-completion.md).

---

## 1. How to use this roadmap

- Prefer **one vertical slice** per milestone: ship code with an **integration test** that proves a branch story end-to-end (see [.cursor/rules/bankcore-planning.mdc](../.cursor/rules/bankcore-planning.mdc)).
- When posting rules, reversal semantics, or GL ownership change, add or update an **ADR** (see [.cursor/rules/bankcore-docs-and-adrs.mdc](../.cursor/rules/bankcore-docs-and-adrs.mdc)).
- Large **Phase 1** work below is intentionally split into **1A–1G** so merges stay reviewable.
- **Informal workstream labels:** e.g. **Workstream 5** = a documentation pass that reconciles this roadmap and canonical docs with **shipped** code (no new product scope in that pass alone).

---

## 2. Guiding principles

1. **Financial integrity** — Double-entry correctness, balanced journals, immutable posted history, **reversals as new events + compensating journals** (never silent edits). Aligns with [ADR-0002](adr/0002-operational-event-model.md), [ADR-0003](adr/0003-posting-journal-architecture.md), [ADR-0010](adr/0010-ledger-persistence-and-seeded-coa.md).
2. **Branch-safe MVP** — Framing from [01-mvp-vs-core.md §5](concepts/01-mvp-vs-core.md): *“Can we run a branch safely?”*
3. **Single path to ledger truth** — Controllers orchestrate; **only** posting commands persist `journal_entries` / `journal_lines`.
4. **Concept doc vs slice-1 ADR** — [ADR-0011](adr/0011-accounts-deposit-vertical-slice-mvp.md) scoped **slice 1** to single-owner demand deposits and deferred **full** joint and **product configuration** depth. This repo shipped **holds** and **teller sessions** in Phase 1 ([ADR-0013](adr/0013-holds-available-and-servicing-events.md), [ADR-0014](adr/0014-teller-sessions-and-control-events.md)), then **narrow Phase 2** work for two-party joint at open, `deposit_products` FK, observability reads, event catalog + fees, supervisor business-date close, and optional drawer variance GL (**§7**). The [MVP concept](concepts/01-mvp-vs-core.md) still describes a **broader** institution MVP (e.g. full joint servicing, engines) beyond those narrows.

---

## 3. Module mapping

| Theme | Primary home (module catalog) |
| ----- | ----------------------------- |
| Operational intent, idempotency | `Core::OperationalEvents` |
| Posting batches, templates | `Core::Posting` |
| GL, journals, COA | `Core::Ledger` |
| Processing / business date | `Core::BusinessDate` |
| Customer (CIF) | `Party` |
| Deposit contracts | `Accounts` |
| Product configuration (later) | `Products` |
| Teller HTTP surface | `app/controllers/teller/*` → domain commands only |
| Drawer sessions, variance, teller cash policy | **`Teller`** ([ADR-0014](adr/0014-teller-sessions-and-control-events.md), [ADR-0015](adr/0015-teller-workspace-authentication.md)); money still records via `Core::OperationalEvents` + `Core::Posting` |

---

## 4. Current position (code checkpoint)

**Done — vertical slice 1 (“one cash deposit”)**  

Verified by [`test/integration/slice1_vertical_slice_proof_test.rb`](../test/integration/slice1_vertical_slice_proof_test.rb): persisted business date (`Core::BusinessDate`), party + deposit account + single-owner participation ([ADR-0011](adr/0011-accounts-deposit-vertical-slice-mvp.md)), `deposit.accepted` (`pending` → `posted`), posting to GL **1110** / **2110** via [`Core::Posting::Commands::PostEvent`](../app/domains/core/posting/commands/post_event.rb), teller JSON `POST` flow with `teller_session_id` where required.

**Also implemented (Phase 1 breadth, beyond that slice proof)**

- **Posting rule registry** — `PostEvent` resolves legs via [`PostingRules::Registry`](../app/domains/core/posting/posting_rules/registry.rb) ([ADR-0012](adr/0012-posting-rule-registry-and-journal-subledger.md)). **Phase 1 core** handlers: **`deposit.accepted`**, **`withdrawal.posted`**, **`transfer.completed`**, **`posting.reversal`**. **Phase 2 narrow** extensions add **`fee.assessed`**, **`fee.waived`**, and (optional env flag) **`teller.drawer.variance.posted`** ([ADR-0019](adr/0019-event-catalog-and-fee-events.md), [ADR-0020](adr/0020-teller-drawer-variance-gl-posting.md)); see §7.
- **Money flows + reversals** — record → post and compensating reversal linkage (`reversal_of_event_id` / `reversed_by_event_id` per [ADR-0002](adr/0002-operational-event-model.md)) in [`operational_events_money_flows_test.rb`](../test/integration/operational_events_money_flows_test.rb).
- **Teller sessions** — open / close / variance / supervisor approve ([ADR-0014](adr/0014-teller-sessions-and-control-events.md)); focused coverage under [`test/integration/teller/`](../test/integration/teller/).
- **Holds** — place / release and interaction with withdrawals ([ADR-0013](adr/0013-holds-available-and-servicing-events.md)); see integration tests above.
- **Operators & HTTP gates** — [`ADR-0015`](adr/0015-teller-workspace-authentication.md); supervisor-only actions documented in [AGENTS.md](../AGENTS.md).
- **Trial balance + EOD readiness (read-only)** — [ADR-0016](adr/0016-trial-balance-and-eod-readiness.md); [`reports_trial_balance_and_eod_test.rb`](../test/integration/teller/reports_trial_balance_and_eod_test.rb).

**Phase 2 narrow slices (also in this repo; detail in §7)**

- **`deposit_products`** + **`deposit_accounts.deposit_product_id`** and cached **`product_code`**; product-aware context on operational-event reads ([ADR-0017](adr/0017-deposit-products-fk-narrow-scope.md)).
- **Two-party joint** at account open (`joint_party_record_id` on teller) ([ADR-0011](adr/0011-accounts-deposit-vertical-slice-mvp.md) §2.3, [ADR-0007](adr/0007-party-account-ownership.md)).
- **Event catalog** — `EventCatalog`, drift vs posting registry, **`GET /teller/event_types`**, **`fee.assessed` / `fee.waived`** + posting ([ADR-0019](adr/0019-event-catalog-and-fee-events.md)).
- **Operational events observability** — **`GET /teller/operational_events`** (bounded `business_date` / range, filters, pagination, envelope) ([ADR-0017](adr/0017-deposit-products-fk-narrow-scope.md) §2.5).
- **Business date close** — supervisor **`POST /teller/business_date/close`** after readiness checks; singleton advance; append-only close audit; **open-day posting invariant** ([ADR-0018](adr/0018-business-date-close-and-posting-invariant.md)). Multi-branch calendars, snapshots, and **day reopen** remain open (§7 table).
- **Optional drawer variance to GL** — **`teller.drawer.variance.posted`** when **`TELLER_POST_DRAWER_VARIANCE_TO_GL`** is enabled ([ADR-0020](adr/0020-teller-drawer-variance-gl-posting.md)).

**Remaining gaps (vs full catalog and institution MVP)**

- **Event types** — [EventCatalog](../app/domains/core/operational_events/event_catalog.rb) and the registry are **bounded**. Narrow Phase 3 events for **`interest.accrued`**, **`interest.posted`**, and **`overdraft.nsf_denied`** are shipped ([ADR-0021](adr/0021-interest-accrual-and-payout-slice.md), [ADR-0023](adr/0023-overdraft-nsf-deny-and-fee.md)); richer composite models, product engines, lifecycle variants, and channel-specific taxonomies remain open.
- **Business date** — beyond the **narrow** close above: multi-branch dates, materialized checkpoints, and reopen policy are not implemented ([ADR-0018](adr/0018-business-date-close-and-posting-invariant.md) vs §7 **Business date close** tail).

**Gap vs [01-mvp-vs-core.md](concepts/01-mvp-vs-core.md) (institution MVP vs this repo)**

- **In repo today:** Phase 1 breadth bullets above **plus** Phase 2 narrow slices (preceding subsection): same **single open business date** and ledger-first posture unless extended by product.
- **Partial / Phase 2+ or Phase 3:** **Full “day closed”** orchestration (multi-branch, checkpoints, reopen) and **multi-branch / multi-entity GL**; **full [ADR-0007](adr/0007-party-account-ownership.md)** (additional roles, effective dating, post-open add/remove); **[ADR-0005](adr/0005-product-configuration-framework.md)** resolvers and **per-product GL** mapping; **full-text / multi-branch** event index (§7 **Observability** tail); **available balance** strategy and **holds** depth beyond MVP authorization ([ADR-0004](adr/0004-account-balance-model.md), §12); fee and interest **engines** (Phase 3).
- **Teller vs supervisor** — identity and supervisor gates shipped ([ADR-0015](adr/0015-teller-workspace-authentication.md)); finer roles and supervisor-only **read** APIs remain product choice.

---

## 5. Phase 0 — Hygiene (optional / parallel)

| Item | Status |
| ---- | ------ |
| Align ADR prose with slice 1 implementation (business date, `source_account_id`, partial participation index on `deposit_account_parties`, `RecordEvent` idempotency fingerprint per [ADR-0002 §7.3](adr/0002-operational-event-model.md)) | **Done** — [ADR-0011](adr/0011-accounts-deposit-vertical-slice-mvp.md), [ADR-0010 §5](adr/0010-ledger-persistence-and-seeded-coa.md), [ADR-0007 §2.7](adr/0007-party-account-ownership.md), [ADR-0002 §7.3 / §8.1](adr/0002-operational-event-model.md). |
| `bin/rails zeitwerk:check` in CI | **Done** — [`.github/workflows/ci.yml`](../.github/workflows/ci.yml) runs Zeitwerk before tests. |

---

## 6. Phase 1 — Branch-safe MVP core

**Goal:** Teller can deposit, withdraw, and transfer; cash drawer reconciles to GL; books prove out; mistakes are reversed with compensating journals and supervisor gates.

### 6.1 Sub-phases (recommended merge order)

| Id | Deliverable | Notes |
| -- | ----------- | ----- |
| **1A** | **Posting rule abstraction** | **Shipped (MVP):** [`PostingRules::Registry`](../app/domains/core/posting/posting_rules/registry.rb) + [ADR-0012](adr/0012-posting-rule-registry-and-journal-subledger.md). |
| **1B** | **Core money movement events** | **Shipped (MVP):** `deposit.accepted`, **`withdrawal.posted`**, **`transfer.completed`** via `RecordEvent` + `PostEvent`; see [`operational_events_money_flows_test.rb`](../test/integration/operational_events_money_flows_test.rb). |
| **1C** | **Teller session + cash control** | **Shipped (MVP):** `teller_sessions`, open/close, variance threshold → **`pending_supervisor`**, **`approve_variance`** ([ADR-0014](adr/0014-teller-sessions-and-control-events.md)). **Optional (Phase 2):** GL posting for drawer variance via **`teller.drawer.variance.posted`** when **`TELLER_POST_DRAWER_VARIANCE_TO_GL`** is on ([ADR-0020](adr/0020-teller-drawer-variance-gl-posting.md)). Drawer/location depth beyond MVP remains product follow-up. |
| **1D** | **Reversals** | **Shipped (MVP):** `posting.reversal`, `RecordReversal`, FK columns, compensating journals ([ADR-0002](adr/0002-operational-event-model.md), [ADR-0012](adr/0012-posting-rule-registry-and-journal-subledger.md)). |
| **1E** | **Minimum balance model** | **Partial:** holds + **available** checks on configured paths ([ADR-0013](adr/0013-holds-available-and-servicing-events.md), [ADR-0004](adr/0004-account-balance-model.md)); deeper balance projections = Phase 2/3. |
| **1F** | **Trial balance + EOD gates** | **MVP read APIs shipped:** `GET /teller/reports/trial_balance`, `GET /teller/reports/eod_readiness` ([ADR-0016](adr/0016-trial-balance-and-eod-readiness.md)). **Supervisor day close + posting invariant:** Phase 2 narrow slice [ADR-0018](adr/0018-business-date-close-and-posting-invariant.md). |
| **1G** | **RBAC** | **Foundation shipped:** **`operators`**, **`X-Operator-Id`**, supervisor gates on **`POST /teller/reversals`**, **`override.approved`**, **`POST /teller/teller_sessions/approve_variance`** ([ADR-0015](adr/0015-teller-workspace-authentication.md)). Finer roles / EOD policy layers = product follow-up. |

### 6.2 Phase 1 exit criteria

- All three flows (deposit, withdraw, transfer) run through **record → post → balanced journal**.  
- Drawer session lifecycle works and ties to teller activity.  
- At least one **reversal** path is demonstrated with **two** posted events and **two** journals, linked per ADR-0002.  
- Trial balance and session closure are part of an **EOD discipline** (manual or automated).  
- Supervisor approval exists for configured exceptions.

---

## 7. Phase 2 — Operational hardening

| Track | Content |
| ----- | ------- |
| **Ownership** | **Narrow two-party joint at open shipped:** `OpenAccount` + Teller `joint_party_record_id` ([ADR-0011](adr/0011-accounts-deposit-vertical-slice-mvp.md) §2.3, [ADR-0007](adr/0007-party-account-ownership.md)). Full ADR-0007 surface (additional roles at open, effective-dating edge cases, post-open add/remove) remains open. |
| **Products** | **Narrow slice shipped:** `deposit_products` + `deposit_accounts.deposit_product_id` + cached `product_code` ([ADR-0017](adr/0017-deposit-products-fk-narrow-scope.md)). Full ADR-0005 resolvers / per-product GL remain open. |
| **Event catalog** | **Narrow slice shipped:** code-first `EventCatalog`, drift checks vs posting registry, **`GET /teller/event_types`**, **`fee.assessed` / `fee.waived`** with posting rules and compensating waive path ([ADR-0019](adr/0019-event-catalog-and-fee-events.md)). Later Phase 3 slices add shipped catalog entries for **`interest.accrued`**, **`interest.posted`**, and **`overdraft.nsf_denied`** (§8). **Deferred:** richer payload schemas, lifecycle metadata, documentation drift checks, and channel-specific taxonomies. |
| **Observability** | **Narrow slice shipped:** `GET /teller/operational_events` — bounded `business_date` / range, product filters, envelope (`current_business_on`, `posting_day_closed`), nested account product fields, posting/journal ids ([ADR-0017](adr/0017-deposit-products-fk-narrow-scope.md) §2.5). Full-text / multi-branch index remains open. |
| **Business date close** | **Narrow slice shipped:** supervisor **`POST /teller/business_date/close`** after ADR-0016 readiness; singleton advance + append-only close audit; **open-day posting invariant** (ADR-0018). Multi-branch, snapshots, day reopen remain open. |
| **GL drawer variance (optional)** | **Narrow slice shipped (env flag):** **`teller.drawer.variance.posted`** from **`CloseSession`** / **`ApproveSessionVariance`** when **`TELLER_POST_DRAWER_VARIANCE_TO_GL`** is on; posting **1110** / **5190** ([ADR-0020](adr/0020-teller-drawer-variance-gl-posting.md)). |

**Phase 2 — current position (narrow slices)**  

All **six** Phase 2 tracks above have a **shipped narrow slice** in this repo; each row’s trailing sentence still lists **deferred** scope (full ADR-0007, ADR-0005 resolvers, interest/NSF events, FTS/multi-branch observability, multi-branch business date / reopen, etc.). Treat **§4** + this table as the checkpoint for “what runs in branch today” vs “what remains open.”

---

## 8. Phase 3 — Product and financial depth

Phase 3 status is tracked in the table below and the accepted ADRs linked from each row.

| Track | Current position |
| --- | --- |
| **Interest engine** | **Narrow slice shipped:** explicit `system`-channel `interest.accrued` / `interest.posted` events, posting rules **5100 / 2510 / 2110**, payout linkage, duplicate-payout guard, and accrual reversal guard ([ADR-0021](adr/0021-interest-accrual-and-payout-slice.md)). **Deferred:** rate engine, day-count conventions, compounding, product interest profiles, sub-minor/microcent accumulator tables, and periodic scheduler. |
| **Fee engine** | **Narrow slice shipped:** product-owned `deposit_product_fee_rules`, active monthly-maintenance resolver, `Accounts::Commands::AssessMonthlyMaintenanceFees`, deterministic idempotency, and `fee.assessed` audit reference convention ([ADR-0022](adr/0022-monthly-maintenance-fee-engine.md)). **Deferred:** broader fee catalog, waiver/condition rules, richer schedules, fee profiles, and statement-copy fees. |
| **Holds depth** | **Narrow slice shipped:** deposit-linked holds reference a posted `deposit.accepted`, enforce same-account/currency and active-hold sum limits, and block deposit reversal while active linked holds remain ([ADR-0013](adr/0013-holds-available-and-servicing-events.md)). **Deferred:** expiration engine, partial release/adjust workflows, Reg CC / collected-funds schedules. |
| **Overdraft handling** | **Narrow slice shipped:** product-owned `deposit_product_overdraft_policies`, deny-NSF authorization path for withdrawals/transfers, no-GL `overdraft.nsf_denied` audit event, and forced NSF `fee.assessed` side effect ([ADR-0023](adr/0023-overdraft-nsf-deny-and-fee.md)). **Deferred:** allowed overdraft limits, opt-in/eligibility rules, representment, returned-item lifecycle, and separate NSF GL mapping. |
| **Customer-visible history and statements** | **Narrow slice shipped:** product-owned `deposit_product_statement_profiles`, `Deposits::Commands::GenerateDepositStatements`, immutable `deposit_statements` JSON snapshots, and line items derived from posted GL **2110** journal lines plus selected no-GL servicing events ([ADR-0024](adr/0024-customer-visible-history-and-statements.md)). **Deferred:** teller/customer HTTP surface, PDF/document generation, delivery preferences, notifications, daily reporting snapshots, and statement fees. |

**Phase 3 — current position (narrow slices)**  

All **five** Phase 3 tracks above have a **shipped narrow slice** in this repo. The table is the checkpoint for “what runs in branch today”; each row’s trailing sentence still lists the deeper product and operational scope that remains open.

---

## 9. Phase 3.5 — Internal workspace UI enablement

Phase 3.5 is an internal Rails HTML workspace phase over the Phase 0-3 domain surface. It adds **branch**, **ops**, and **admin/product** workspaces while preserving the existing JSON `/teller` APIs and `X-Operator-Id` behavior. See [ADR-0025](adr/0025-internal-workspace-ui.md).

- **Branch workspace:** branch-local UI that initially wraps teller session and transaction workflows.
- **Ops workspace:** EOD readiness, trial balance, operational event search/detail, close packages, and exception review.
- **Admin/Product workspace:** product configuration inspection first, then guarded config edits in later slices.

**Phase 3.5b refinement:** extend those workspaces toward parity with shipped Phase 0-3 operations: branch session lifecycle with expected-cash close display, transfer/hold/reversal/override/event screens; ops close package and exception queues; admin product readiness and richer product detail. This remains an internal staff UI pass and does **not** introduce new event types, posting semantics, GL mappings, cash-location depth, or external channels.

---

## 10. Phase 4 — Channels and ecosystem

Phase 4 adds servicing and channel capability in controlled slices. It should **not** absorb every deferred product, reporting, compliance, or scale item; pull those forward only when they reduce risk for servicing or the selected external channel.

| Slice | Status | Scope |
| --- | --- | --- |
| **4.1 Branch CSR servicing** | **Shipped** | Branch-hosted customer/account servicing over existing domain queries and guarded operational actions. Shipped surface includes customer search / customer 360, deposit account profile, account activity, holds, statement metadata, and guarded hold placement/release, fee waiver, and reversal forms. Non-cash servicing writes use operational-event channel **`branch`** with `actor_id`; GL-backed fee waivers and reversals still post only through `Core::Posting`. See [ADR-0026](adr/0026-branch-csr-servicing.md) and [`branch_customer_servicing_test.rb`](../test/integration/branch_customer_servicing_test.rb). |
| **4.2 Event catalog and channel metadata** | **Shipped** | `Core::OperationalEvents::EventCatalog` now carries lifecycle, allowed-channel, financial-impact, customer/statement visibility, payload-schema, and support-search metadata with drift checks across the catalog and [operational event specs](operational_events/). |
| **4.3 Product resolver baseline** | **Shipped** | Products-owned effective-dated resolver helpers and a deposit product behavior resolver now cover monthly maintenance, deny-NSF overdraft, and monthly statement profile behavior. Full product-engine breadth and per-product GL mapping remain deferred until a selected money-moving channel requires them. |
| **4.4 Servicing depth after CSR** | **Shipped** | Holds now include type/reason/expiration metadata, customer-safe explanations, and idempotent due-expiration using no-GL `hold.released` events. Branch servicing now shows current/historical account-party relationships and supports supervisor-only post-open `authorized_signer` add/end workflows with Accounts-owned audit rows. Partial hold release/adjustment, ownership changes, and broader role authority remain deferred. |
| **4.5 Support observability and close readiness** | **Shipped** | Ops support search now includes support-key filters for reference, idempotency, and reversal links, with query-aligned operational-event indexes. The close package now shows read-only EOD impact evidence by event status, channel, and type, while keeping materialized balance snapshots and branch-scoped business dates deferred. |
| **4.6 External read APIs** | **Next recommended** | Add customer/partner/fintech read contracts over existing account, event, product, statement, and ledger-derived state. [ADR-0027](adr/0027-external-read-api-boundary.md) defines the external trust boundary, redaction, rate-limit, audit, pagination, and response-contract requirements. Do not reuse Branch browser sessions or teller headers. |
| **4.7 First money-moving channel** | Planned | Prefer ACH receipt ingestion as the first external money-moving slice. ADR required before implementation: file/item idempotency, event taxonomy, settlement GL, returns, cutoffs/EOD blocking, reconciliation, and support search. |

Wires, cards/ATM, full multi-branch or multi-entity GL, document delivery, broad reporting snapshots, allowed-overdraft/representment, and dispute/provisional-credit workflows remain deferred unless the selected Phase 4 channel explicitly requires them.

---

## 11. Phase 5 — Compliance and scale

- AML monitoring, CTR, sanctions workflows as applicable.  
- Fraud signals and risk scoring.  
- Multi-branch / multi-entity GL and consolidation reporting.

---

## 12. Near-term recommendation

**Historical (1A-era sequencing):** shipping posting rules together with withdrawal, session skeleton, and one reversal type in tight increments—each with a **green integration test**—was the fastest path to credible teller balancing and audit posture.

**Current:** use **§4**, **§7**, **§8**, and **§10** as the live checkpoint (Phase 1 breadth, Phase 2 and Phase 3 narrow tracks, plus Phase 4.1-4.5 Branch servicing, event catalog, product resolver, servicing depth, and support observability slices); when adding `event_type` values or crossing module boundaries, extend an integration proof per [.cursor/rules/bankcore-planning.mdc](../.cursor/rules/bankcore-planning.mdc).

---

## 13. Open decisions (track in ADRs or short design notes)

- ~~Canonical **`event_type`** strings for each reversal variant~~ — **`posting.reversal`** + `RecordReversal` ([ADR-0012](adr/0012-posting-rule-registry-and-journal-subledger.md)); see [compensating-reversal.md](operational_events/compensating-reversal.md).  
- ~~**Module ownership** for drawer cash vs approval workflow~~ — **Sessions / variance:** **`Teller`** ([ADR-0014](adr/0014-teller-sessions-and-control-events.md)); **optional GL cash adjustment** for drawer variance ships behind **`TELLER_POST_DRAWER_VARIANCE_TO_GL`** ([ADR-0020](adr/0020-teller-drawer-variance-gl-posting.md)).  
- ~~**Available balance**: compute-on-read vs materialized projection for volume.~~ — **Resolved:** default **compute-on-read**; materialized projection allowed only with invalidation + rebuild ADR ([ADR-0004](adr/0004-account-balance-model.md) §13.3).  
- ~~How **trial balance** is exposed~~ — **MVP:** teller JSON **`GET /teller/reports/trial_balance`** and **`GET /teller/reports/eod_readiness`** ([ADR-0016](adr/0016-trial-balance-and-eod-readiness.md)); operator PDF/HTML reports remain product choice.

---

## 14. References

| Document | Role |
| -------- | ---- |
| [01-mvp-vs-core.md](concepts/01-mvp-vs-core.md) | MVP vs full system, “branch safely” framing |
| [00-functional-domains.md](concepts/00-functional-domains.md) | Business scope map |
| [bankcore-module-catalog.md](architecture/bankcore-module-catalog.md) | Monolith boundaries |
| [101-operational_event_enums_concept.md](concepts/101-operational_event_enums_concept.md) | Longer-term parent/component event modeling ideas |
| [AGENTS.md](../AGENTS.md) | Stack, Docker, Cursor rules index |
| [ADR-0015](adr/0015-teller-workspace-authentication.md) | Teller workspace `operators`, `X-Operator-Id`, supervisor gates |
| [ADR-0016](adr/0016-trial-balance-and-eod-readiness.md) | Trial balance query + EOD readiness reads |
| [ADR-0017](adr/0017-deposit-products-fk-narrow-scope.md) | `deposit_products` + account FK + observability reads §2.5 (narrow Phase 2 slice) |
| [ADR-0018](adr/0018-business-date-close-and-posting-invariant.md) | Business date close + open-day posting invariant (narrow Phase 2 slice) |
| [ADR-0019](adr/0019-event-catalog-and-fee-events.md) | Event catalog metadata, `GET /teller/event_types`, `fee.assessed` / `fee.waived` (narrow Phase 2 slice) |
| [ADR-0020](adr/0020-teller-drawer-variance-gl-posting.md) | Optional GL posting for teller drawer variance (`teller.drawer.variance.posted`) |
| [ADR-0025](adr/0025-internal-workspace-ui.md) | Phase 3.5 internal Rails HTML workspaces (`branch`, `ops`, `admin`) and JSON `/teller` preservation |
