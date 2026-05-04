# Bank transaction capability taxonomy

## Purpose

This concept complements [302-teller-transaction-surface.md](302-teller-transaction-surface.md) with **institution-wide transaction capability families (F1–F17)**—what the bank can record, control, and post—not “everything the teller domain owns.” **Real branch work spans deposit movements, instruments, service economics, custody, rails, lending, compliance, and exceptions.**

**302** stays focused on **teller-adjacent execution surfaces** (JSON `/teller` and Branch teller line); **this document** classifies capabilities regardless of who initiates them.

**Module mapping** follows [bankcore-module-catalog.md](../architecture/bankcore-module-catalog.md). **MVP vs phased scope** follows [01-mvp-vs-core.md](01-mvp-vs-core.md): rows are labeled **Shipped**, **Near-term (T-phase)**, or **Post-MVP** without changing MVP boundaries by itself.

Concrete **`event_type`**, **`allowed_channels`** (from [ADR-0019](../adr/0019-event-catalog-and-fee-events.md) `EventCatalog`), and commands: **[master-transaction-capability-registry.md](../architecture/master-transaction-capability-registry.md)**.

---

## Capability vs execution channel

Two axes must stay separate:

| Axis | Meaning |
| --- | --- |
| **Capability family (F1–F17)** | What kind of banking activity this is—domain grouping for ownership and sequencing. |
| **Execution channel / surface** | **Who produced** the durable row or initiated the command: JSON **`teller`**, Branch **`branch`**, ingestion **`batch`**, engines **`system`**, plus HTML lanes ([ADR-0037](../adr/0037-internal-staff-authorized-surfaces.md)). |

Persisted **`operational_events`** carry **`event_type`** (business fact) and **`channel`** (producer). **`Teller`** as a **Rails domain** owns **session lifecycle and workstation-facing orchestration**, not every family below—many types are **`system`** or **`batch`** only (see `app/domains/core/operational_events/event_catalog.rb`).

**Teller line (human) relevance:** strongest on cash-affecting account moves (**F1**), instruments (**F2**), custody (**F4**), settlement (**F11** session/variance), multi-tender (**F17**), and some exceptions (**F5**). **Interest accrual/posting**, bulk ACH lifecycle beyond receipt slice, and many compliance filings are normally **`system`** / **Ops** workflows—not owned by teller domain logic.

---

## Design principle

**Bank capabilities are not all deposit-account transfers.** Some rows are instrument conversion, cash-for-instrument exchange, service revenue capture, conditional availability / holds, custody-only moves, rails settlement, or operational controls with no immediate customer balance effect. Each family must declare **ownership**, **GL posture**, **DDA involvement**, **custody**, **holds**, and **close/EOD relevance** before implementation.

---

## 1. Transaction families (summary)

| Family | Intent | MVP posture |
| --- | --- | --- |
| **F1 — Deposit account transactions** | Credit/debit DDA with durable event + posting path where applicable | **Shipped** (cash deposit/withdrawal/transfer, fees, holds, reversals) |
| **F2 — Instrument transactions** | Checks and similar items: acceptance, holds, returns, eventual availability | **Phased** — [T1](#3-phased-slices-t1t4) check deposit spike path |
| **F3 — Service and non-account receipts** | Branch fees and charges that may not present as a simple DDA debit/credit pair | **Partial** — account-linked `fee.*`; broader misc receipts **T3** |
| **F4 — Cash custody operations** | Vault/drawer/shipment/count/variance | **Shipped** foundation ([ADR-0031](../adr/0031-cash-inventory-and-management.md), [ADR-0039](../adr/0039-teller-session-drawer-custody-projection.md)) |
| **F5 — Operational exceptions** | Overrides, approvals, reversals, blockers | **Partial** — controls + EOD readiness; richer classification **T4** |
| **F6 — Electronic payments and network rails** | ACH (partial receipt), wires, cards, exceptions | **Partial** — inbound ACH credit slice ([ADR-0028](../adr/0028-ach-receipt-ingestion.md)); origination/returns/wires **Post-MVP** |
| **F7 — Loan-related transactions** | Payments, payoffs, advances, loan fees | **Post-MVP** — needs credit account model + ADRs |
| **F8 — Account maintenance and servicing** | Restrictions, close, stop-pay, contact updates | **Partial** — restriction/unrestrict/close events shipped on Branch channel; stop-pay and Party edits **Post-MVP** |
| **F9 — Cash-in / cash-out without primary DDA** | Non-customer check cashing, FX, money orders | **Post-MVP** |
| **F10 — Safe custody and non-cash assets** | Safe deposit logs, night drop, document custody | **Post-MVP** |
| **F11 — Teller settlement and reconciliation** | Session lifecycle, drawer variance GL, suspense clearing | **Partial** — sessions + drawer variance event shipped; suspense clearing **Post-MVP** |
| **F12 — Fraud, risk, compliance (staff inputs)** | CTR/SAR workflows, identity overrides, aggregation | **Post-MVP** |
| **F13 — Third-party / agency** | Bill pay, taxes, remittances | **Post-MVP** |
| **F14 — Account funding / origination** | Open account + initial funding, multi-tender onboarding | **Partial** — account open + can compose **F1** deposits; formal bundle **Near-term** |
| **F15 — Interest and product lifecycle** | Interest payout, CD maturity/penalties | **Partial** — `interest.*` shipped **`system`** channel; CDs **Post-MVP** |
| **F16 — Internal bank operations** | Branch balancing, GL corrections | **Post-MVP** |
| **F17 — Multi-tender / split transactions** | Cash + check bundles, split disbursements | **Post-MVP** — composition pattern; not a single `event_type` today |

---

## 2. Capability matrix (by family)

Legend: **DDA** = deposit account balance effect; **GL** = posts via `Core::Posting`; **Drawer** = teller-session / `Cash` drawer projection path; **Hold** = `Accounts` hold or item hold pattern; **Sup** = supervisor or elevated capability common case.

| Family | Typical activities | Primary owners | DDA | GL | Drawer | Hold | Sup | Close / EOD |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| F1 | Cash deposit, withdrawal, transfer | `Core::OperationalEvents`, `Accounts`, `Teller` | Yes | Yes | Yes when cash + posted ([ADR-0039](../adr/0039-teller-session-drawer-custody-projection.md)) | Optional (`hold.placed`) | Reversal / some fees | Pending vs posted events; sessions closed |
| F1 | Fee assess / waive | `Core::OperationalEvents`, `Core::Posting` | Yes | Yes | No | — | Waive | Same as F1 |
| F2 | Check deposit (item in, provisional credit) | `Core::*`, future **`Instruments`** or `Accounts` extension | Yes (policy-dependent) | TBD per ADR | TBD (often no cash drawer delta until negotiated) | **Reg‑CC-style** availability | Overrides | Pending items / holds |
| F2 | Check cashing, official check | Future `Instruments` / posting slice | Often | Yes | Often cash-out | Risk limits | Often | Outstanding liabilities |
| F3 | Wire fee, misc branch charge without simple DDA leg | TBD (`Core` + revenue/suspense pattern) | Maybe | Yes | Maybe | — | Sometimes | Posted vs suspense |
| F4 | Vault ↔ drawer, shipments, counts | `Cash` | No | Exceptions only | Yes | — | Approvals | Custody variances, movements |
| F5 | Override, NSF denial | `Core::OperationalEvents`, `Workspace` | Optional | Usually no | No | — | Often | Exceptions list |
| F6 | ACH / wire / card rails | `Integration`, future rails | Often | Often | Rare | No | Often | Settlement / pending queues |
| F7 | Loan payment / payoff | Future `Loans` / credit core | Yes | Yes | Conditional | Product rules | Often | Delinquency / payoff evidence |
| F8 | Account freeze, close, servicing | `Accounts`, `Party`, `Branch` | No / conditional | Fee legs only where applicable | No | Optional | Often | Servicing audit |
| F9 | Non-DDA cash operations | TBD | Suspense-dependent | Often | Yes | Limits | Almost always | High-risk queues |
| F10 | Safe deposit / night drop | TBD | Usually no | Conditional | No | Dual control | Sometimes | Custody audit |
| F11 | Session close, suspense bridge | `Teller`, `Cash`, `Core` | Optional variance GL | Conditional | Session/drawer | — | Supervisor | Close package |
| F12 | Compliance triggers | `Compliance`, `Workspace` | Usually no | No | No | — | SAR/CTR workflow | Regulatory evidence |
| F13 | Agency products | TBD partner rails | Partner-dependent | Partner-dependent | Conditional | Partner rules | Partner policy | Settlement files |
| F14 | Open + fund account | `Accounts`, `Party` | Opening often no GL | Funding yes | Conditional | KYC gates | Sometimes | Onboarding checklist |
| F15 | Interest / CD lifecycle | `Deposits`, `Core::Posting` | Yes | Yes | No | Product rules | Ops/teller explain | Statement / maturity |
| F16 | Internal corrections | `Core::Ledger`, `Cash` | Yes | Yes | Sometimes | Dual control | Always | Ops-only evidence |
| F17 | Multi-tender bundles | **Composition** of F1/F2/F9 | Per leg | Per leg | Per leg | Per leg | Often | Receipt / drawer totals |

Rows marked **TBD** require an ADR before coding posting, reversal, or GL semantics (see [roadmap-branch-operations.md](../roadmap-branch-operations.md) boundary rules).

---

## 3. Phased slices (T1–T4)

These **T-phases** are **vertical delivery slices** for sequencing kernel and UX work. They often **start from branch/teller UX pain points** but **cut across domains**—ownership stays with **Instruments**, **Cash**, **`Core::Posting`**, etc., not “the teller module.”

| Slice | Goal | Kernel stress |
| --- | --- | --- |
| **T1** | Check deposit + availability / holds discipline | Instrument identity on events or side tables; hold rules; optional provisional posting pattern |
| **T2** | Check cashing / official-check-style payouts | Cash + liability / clearing semantics; stronger limits and approvals |
| **T3** | Service / non-account fee receipts | Revenue recognition without forcing every receipt through a single DDA shape |
| **T4** | Close package / EOD classification | Read-model grouping by lifecycle: posted, pending, reversed, held, overridden, blocker |

**Spike artifact for T1:** [check-deposit-t1-vertical-slice.md](../spikes/check-deposit-t1-vertical-slice.md) and `rake spike:check_deposit_t1`.

---

## 4. Close-package classification (target)

EOD and supervisor close flows should eventually bucket branch-facing work (not only `operational_events.status`) along dimensions such as:

- **Posted** — financial truth applied (`posted`, journals where applicable).
- **Pending** — recorded but not posted, or awaiting settlement.
- **Reversed** — compensating linkage (`reversed_by_event_id` / reversal rows).
- **Held** — availability reduced (`hold.placed`, future item holds).
- **Overridden** — control rows (`override.*`) authorizing exception paths.
- **Exception** — NSF denial, variance, shipment mismatch, policy rejection evidence.
- **Blocker / warning** — readiness flags ([ADR-0016](../adr/0016-trial-balance-and-eod-readiness.md)); expand as T4 adds families.

Today’s readiness APIs focus on trial balance, pending events, and open sessions; T4 broadens coverage as new families ship.

---

## 5. Related documents

| Document | Role |
| --- | --- |
| [302-teller-transaction-surface.md](302-teller-transaction-surface.md) | Teller-adjacent **execution surface** (MVP matrices) |
| [master-transaction-capability-registry.md](../architecture/master-transaction-capability-registry.md) | Capability codes ↔ shipped `event_type` / channels / commands (subordinate to [ADR-0019](../adr/0019-event-catalog-and-fee-events.md)) |
| [branch-operations-capability-map.md](../architecture/branch-operations-capability-map.md) | Branch activity ↔ commands |
| [ADR-0019](../adr/0019-event-catalog-and-fee-events.md) | Event catalog and discovery |
| [ADR-0037](../adr/0037-internal-staff-authorized-surfaces.md) | Staff surfaces vs domains |
| [ADR-0039](../adr/0039-teller-session-drawer-custody-projection.md) | Teller cash ↔ drawer custody |
| [roadmap-branch-operations.md](../roadmap-branch-operations.md) | Branch sequencing |
