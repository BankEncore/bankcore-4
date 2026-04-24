# BankCORE development roadmap

**Status:** Draft  
**Last reviewed:** 2026-04-26  

This document **sequences** engineering work. It does **not** redefine scope: MVP boundaries stay in [docs/concepts/01-mvp-vs-core.md](concepts/01-mvp-vs-core.md); boundaries and ownership stay in [docs/architecture/bankcore-module-catalog.md](architecture/bankcore-module-catalog.md) and the ADRs under [docs/adr/](adr/).

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
4. **Concept doc vs slice-1 ADR** — [ADR-0011](adr/0011-accounts-deposit-vertical-slice-mvp.md) defers joint accounts, products FK, holds, and drawer sessions **until after** slice 1; the [MVP concept](concepts/01-mvp-vs-core.md) lists joint under “mandatory MVP” at the **institution** level. This roadmap **follows ADR-0011 sequencing**: single-owner and ledger-first, then joint/products in Phase 2.

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

- **Posting rule registry** — `PostEvent` resolves legs via [`PostingRules::Registry`](../app/domains/core/posting/posting_rules/registry.rb) ([ADR-0012](adr/0012-posting-rule-registry-and-journal-subledger.md)); supported `event_type` values today include **`deposit.accepted`**, **`withdrawal.posted`**, **`transfer.completed`**, **`posting.reversal`**.
- **Money flows + reversals** — record → post and compensating reversal linkage (`reversal_of_event_id` / `reversed_by_event_id` per [ADR-0002](adr/0002-operational-event-model.md)) in [`operational_events_money_flows_test.rb`](../test/integration/operational_events_money_flows_test.rb).
- **Teller sessions** — open / close / variance / supervisor approve ([ADR-0014](adr/0014-teller-sessions-and-control-events.md)); focused coverage under [`test/integration/teller/`](../test/integration/teller/).
- **Holds** — place / release and interaction with withdrawals ([ADR-0013](adr/0013-holds-available-and-servicing-events.md)); see integration tests above.
- **Operators & HTTP gates** — [`ADR-0015`](adr/0015-teller-workspace-authentication.md); supervisor-only actions documented in [AGENTS.md](../AGENTS.md).
- **Trial balance + EOD readiness (read-only)** — [ADR-0016](adr/0016-trial-balance-and-eod-readiness.md); [`reports_trial_balance_and_eod_test.rb`](../test/integration/teller/reports_trial_balance_and_eod_test.rb).

**Still slice-1 shaped (narrative)**

- The registry covers a **small fixed set** of `event_type` values — not the full future event catalog (Phase 2+).
- **Formal business-date close** — **narrow supervisor close + posting invariant shipped** ([ADR-0018](adr/0018-business-date-close-and-posting-invariant.md)); **read APIs** plus EOD discipline remain in [ADR-0016](adr/0016-trial-balance-and-eod-readiness.md). Deeper locks, checkpoints, and multi-entity dates are not implemented.

**Gap vs [01-mvp-vs-core.md](concepts/01-mvp-vs-core.md) (institution MVP vs this repo)**

- **In repo today** (single-owner, single–business-date framing): deposits, withdrawals, transfers, reversals with FK columns, teller sessions and variance workflow, holds with available checks for configured paths, trial balance / EOD readiness **GET**s — each cross-linked to ADRs above.
- **Partial / Phase 2+:** **Full “day closed”** orchestration (multi-branch, checkpoints, reopen) and **multi-branch / multi-entity GL** (Phase 2 below); **full joint / multi-party** servicing (3+ at open, post-open add/remove, additional roles) vs institution MVP in the concept doc — **narrow two-party joint at open** is in [ADR-0011](adr/0011-accounts-deposit-vertical-slice-mvp.md) §2.3; **narrow business date close** in [ADR-0018](adr/0018-business-date-close-and-posting-invariant.md); **optional GL cash adjustment** for drawer variance ([ADR-0020](adr/0020-teller-drawer-variance-gl-posting.md), env-flagged); **available / holds** depth beyond MVP authorization ([ADR-0004](adr/0004-account-balance-model.md), Phase 3).
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
| **1C** | **Teller session + cash control** | **Shipped (MVP):** `teller_sessions`, open/close, variance threshold → **`pending_supervisor`**, **`approve_variance`** ([ADR-0014](adr/0014-teller-sessions-and-control-events.md)). Drawer/location depth and **GL cash adjustment** for variance still TBD. |
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
| **Event catalog** | **Narrow slice shipped:** code-first `EventCatalog`, drift checks vs posting registry, **`GET /teller/event_types`**, **`fee.assessed` / `fee.waived`** with posting rules and compensating waive path ([ADR-0019](adr/0019-event-catalog-and-fee-events.md)). **Deferred:** interest (`interest.accrued`, `interest.posted`), NSF / overdraft-style events (separate slices). |
| **Observability** | **Narrow slice shipped:** `GET /teller/operational_events` — bounded `business_date` / range, product filters, envelope (`current_business_on`, `posting_day_closed`), nested account product fields, posting/journal ids ([ADR-0017](adr/0017-deposit-products-fk-narrow-scope.md) §2.5). Full-text / multi-branch index remains open. |
| **Business date close** | **Narrow slice shipped:** supervisor **`POST /teller/business_date/close`** after ADR-0016 readiness; singleton advance + append-only close audit; **open-day posting invariant** (ADR-0018). Multi-branch, snapshots, day reopen remain open. |
| **GL drawer variance (optional)** | **Narrow slice shipped (env flag):** **`teller.drawer.variance.posted`** from **`CloseSession`** / **`ApproveSessionVariance`** when **`TELLER_POST_DRAWER_VARIANCE_TO_GL`** is on; posting **1110** / **5190** ([ADR-0020](adr/0020-teller-drawer-variance-gl-posting.md)). |

---

## 8. Phase 3 — Product and financial depth

- Interest engine (accrual, periodic post, day-count conventions).  
- Fee engine (rules, waivers, conditions).  
- Holds depth (expiration, partial holds, deposit-based holds).  
- Overdraft handling (allow/deny, fee side effects).  
- Customer-visible history and statements (from posted events + journals, not ad-hoc mutation).

---

## 9. Phase 4 — Channels and ecosystem

- ACH, wires, card settlement—**ADR required** when ingestion touches posting ([bankcore-docs-and-adrs.mdc](../.cursor/rules/bankcore-docs-and-adrs.mdc)).  
- CSR / servicing workspace; partner and fintech APIs.

---

## 10. Phase 5 — Compliance and scale

- AML monitoring, CTR, sanctions workflows as applicable.  
- Fraud signals and risk scoring.  
- Multi-branch / multi-entity GL and consolidation reporting.

---

## 11. Near-term recommendation

**Historical (1A-era sequencing):** shipping posting rules together with withdrawal, session skeleton, and one reversal type in tight increments—each with a **green integration test**—was the fastest path to credible teller balancing and audit posture.

**Current:** use **§4** as the live checkpoint; when adding `event_type` values or crossing module boundaries, extend an integration proof per [.cursor/rules/bankcore-planning.mdc](../.cursor/rules/bankcore-planning.mdc).

---

## 12. Open decisions (track in ADRs or short design notes)

- ~~Canonical **`event_type`** strings for each reversal variant~~ — **`posting.reversal`** + `RecordReversal` ([ADR-0012](adr/0012-posting-rule-registry-and-journal-subledger.md)); see [compensating-reversal.md](operational_events/compensating-reversal.md).  
- ~~**Module ownership** for drawer cash vs approval workflow~~ — **Sessions / variance:** **`Teller`** ([ADR-0014](adr/0014-teller-sessions-and-control-events.md)); **optional GL cash adjustment** for drawer variance ships behind **`TELLER_POST_DRAWER_VARIANCE_TO_GL`** ([ADR-0020](adr/0020-teller-drawer-variance-gl-posting.md)).  
- **Available balance**: compute-on-read vs materialized projection for volume.  
- ~~How **trial balance** is exposed~~ — **MVP:** teller JSON **`GET /teller/reports/trial_balance`** and **`GET /teller/reports/eod_readiness`** ([ADR-0016](adr/0016-trial-balance-and-eod-readiness.md)); operator PDF/HTML reports remain product choice.

---

## 13. References

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
