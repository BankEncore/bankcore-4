# BankCORE development roadmap

**Status:** Draft  
**Last reviewed:** 2026-04-22  

This document **sequences** engineering work. It does **not** redefine scope: MVP boundaries stay in [docs/concepts/01-mvp-vs-core.md](concepts/01-mvp-vs-core.md); boundaries and ownership stay in [docs/architecture/bankcore-module-catalog.md](architecture/bankcore-module-catalog.md) and the ADRs under [docs/adr/](adr/).

---

## 1. How to use this roadmap

- Prefer **one vertical slice** per milestone: ship code with an **integration test** that proves a branch story end-to-end (see [.cursor/rules/bankcore-planning.mdc](../.cursor/rules/bankcore-planning.mdc)).
- When posting rules, reversal semantics, or GL ownership change, add or update an **ADR** (see [.cursor/rules/bankcore-docs-and-adrs.mdc](../.cursor/rules/bankcore-docs-and-adrs.mdc)).
- Large **Phase 1** work below is intentionally split into **1A–1G** so merges stay reviewable.

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
| Drawer / session / variance (TBD) | New ADR: likely `Teller` and/or `Workflow` + catalog update |

---

## 4. Current position (code checkpoint)

**Done — vertical slice 1 (“one cash deposit”)**  

Verified by [`test/integration/slice1_vertical_slice_proof_test.rb`](../test/integration/slice1_vertical_slice_proof_test.rb):

- Persisted business date (`Core::BusinessDate`)
- Party (individual), deposit account, single owner participation ([ADR-0011](adr/0011-accounts-deposit-vertical-slice-mvp.md))
- `deposit.accepted` operational event (`pending` → `posted`)
- Posting to GL **1110** / **2110** via [`Core::Posting::Commands::PostEvent`](../app/domains/core/posting/commands/post_event.rb)
- Teller JSON routes: `POST /teller/parties`, `POST /teller/deposit_accounts`, `POST /teller/operational_events`, `POST /teller/operational_events/:id/post`

**Still slice-1 shaped**

- `PostEvent` only recognizes **`deposit.accepted`** and uses **hard-coded** GL legs (no rule resolver).
- No withdrawals, transfers, reversals, trial balance API, drawer sessions, holds, or RBAC beyond whatever the controllers implicitly assume.

**Gap vs [01-mvp-vs-core.md](concepts/01-mvp-vs-core.md) MVP checklist**

- Withdrawals / internal transfers  
- Teller drawer session control and cash variance  
- End-to-end reversals (including `reversal_of_event_id` / `reversed_by_event_id` per [ADR-0002 §4 / column roadmap](adr/0002-operational-event-model.md))  
- Available balance and holds ([ADR-0004](adr/0004-account-balance-model.md))  
- Trial balance visibility and EOD reconciliation discipline  
- Teller vs supervisor roles and approval paths  
- Joint and multi-party accounts (deferred in ADR-0011; listed under MVP in the concept doc for the **full** institution MVP)

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
| **1A** | **Posting rule abstraction** | Introduce a resolver or template registry so `PostEvent` is not a growing `case` on `event_type`. ADR if invariant or ownership changes. |
| **1B** | **Core money movement events** | Add `event_type` values and commands (e.g. `withdrawal.disbursed`, `transfer.completed`) with mappings: cash out (credit cash / debit liability), transfer (liability ↔ liability). Extend [slice proof test](../test/integration/slice1_vertical_slice_proof_test.rb) or add sibling tests per flow. |
| **1C** | **Teller session + cash control** | `teller_sessions`, drawer/location model, open/close, expected vs actual, variance; supervisor approval for material variance. **New ADR** + catalog row for owning module. |
| **1D** | **Reversals** | Implement reversal FKs from [ADR-0002](adr/0002-operational-event-model.md) column roadmap; compensating journals only; original event stays `posted`. |
| **1E** | **Minimum balance model** | `holds` + derived or persisted **available** for authorization: `available = ledger - holds` ([ADR-0004](adr/0004-account-balance-model.md)). |
| **1F** | **Trial balance + EOD gates** | Read model or report: GL trial balance; branch checks (sessions closed, books balanced). |
| **1G** | **RBAC** | Actor on events; roles **teller** / **supervisor**; approvals for reversal, override, variance. |

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
| **Ownership** | Joint and additional roles per [ADR-0007](adr/0007-party-account-ownership.md); effective dating already in ADR—enforce in commands and indexes. |
| **Products** | `deposit_products` (or equivalent) per [ADR-0005](adr/0005-product-configuration-framework.md); migrate off literal `slice1_demand_deposit` stub toward FK + config. |
| **Event catalog** | Fees (`fee.assessed`, `fee.waived`), interest (`interest.accrued`, `interest.posted`), NSF / overdraft-style events as needed—each with posting templates. |
| **Observability** | Searchable event index; filters by date, account, teller; traceability **event ↔ posting batch ↔ journal ↔ session**. |
| **Business date close** | Formal “day closed” transition, optional balance snapshots, lock prior day posting—extend `Core::BusinessDate` commands with ADR if semantics split. |

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

After **1A (posting rules)**, ship **1B (withdrawal)** together with **1C (session skeleton)** and **1D (one reversal type)** in tight increments, each with a **green integration test**. That bundle unlocks real teller balancing and audit posture fastest.

---

## 12. Open decisions (track in ADRs or short design notes)

- Canonical **`event_type`** strings for each reversal variant vs [ADR-0002](adr/0002-operational-event-model.md) registry.  
- **Module ownership** for drawer cash vs approval workflow.  
- **Available balance**: compute-on-read vs materialized projection for volume.  
- How **trial balance** is exposed (internal JSON vs operator report vs both).

---

## 13. References

| Document | Role |
| -------- | ---- |
| [01-mvp-vs-core.md](concepts/01-mvp-vs-core.md) | MVP vs full system, “branch safely” framing |
| [00-functional-domains.md](concepts/00-functional-domains.md) | Business scope map |
| [bankcore-module-catalog.md](architecture/bankcore-module-catalog.md) | Monolith boundaries |
| [101-operational_event_enums_concept.md](concepts/101-operational_event_enums_concept.md) | Longer-term parent/component event modeling ideas |
| [AGENTS.md](../AGENTS.md) | Stack, Docker, Cursor rules index |
