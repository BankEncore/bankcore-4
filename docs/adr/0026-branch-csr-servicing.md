# ADR-0026: Branch-hosted CSR servicing

**Status:** Accepted  
**Date:** 2026-04-25  
**Aligns with:** [module catalog](../architecture/bankcore-module-catalog.md) §7, [ADR-0015](0015-teller-workspace-authentication.md), [ADR-0025](0025-internal-workspace-ui.md), [roadmap](../roadmap.md) Phase 4

---

## 1. Context

Phase 4 introduces channels and servicing surfaces. The immediate need is a customer service representative (CSR) surface where staff can find a customer, inspect accounts, understand recent activity, and perform guarded operational actions.

BankCORE already has an internal Rails HTML `branch` workspace. That workspace wraps teller-adjacent branch operations and already exposes party creation, account opening, holds, reversals, operational events, and transaction forms. A separate `customer_service` workspace would duplicate much of the Branch navigation, authentication, and account-servicing surface before there is a distinct call-center or back-office operating model.

CSR servicing should therefore extend Branch as a customer/account servicing area. This is still an internal staff UI. It is not a customer portal, partner API, fintech API, ACH/wire/card channel, or external identity boundary.

---

## 2. Decision

Phase 4.1 adds Branch-hosted CSR servicing in three slices:

1. **Phase 4.1A — Branch servicing foundation:** customer/account search, customer 360, account profile, balances, holds, statement metadata, and account activity/history.
2. **Phase 4.1B — Guarded operational actions:** account-centered forms for existing kernel-backed servicing actions: place/release hold, waive fee, and reverse eligible events.
3. **Phase 4.1C — Role refinement and controls:** explicit access tests, role gates, confirmations, audit evidence, and a decision on whether a dedicated `customer_service` operator role is needed later.

Controllers remain under `app/controllers/branch/`. They validate and normalize input, call domain queries/commands, and prepare view state. They must not compute balances, construct journal lines, embed posting rules, or bypass the operational-event/posting path.

---

## 3. Scope

### 3.1 Read surfaces

Phase 4.1A may add Branch screens for:

- customer or party search
- party/customer profile
- linked deposit accounts
- deposit account profile
- product summary
- ledger and available balance display
- active and historical holds
- statement metadata
- account activity from ledger-backed statement activity and operational-event timelines

The read model should be backed by domain queries:

- `Party::Queries::*` owns party search and profile reads.
- `Accounts::Queries::*` owns deposit-account profile, ownership, and hold reads.
- `Deposits::Queries::*` owns statement and statement-activity reads.
- `Products::Queries::*` owns product/rule summary reads.
- `Core::OperationalEvents::Queries::*` owns operational-event timelines.

### 3.2 Guarded actions

Phase 4.1B may expose only existing servicing actions:

- `Accounts::Commands::PlaceHold`
- `Accounts::Commands::ReleaseHold`
- `Core::OperationalEvents::Commands::RecordEvent` for `fee.waived`
- `Core::OperationalEvents::Commands::RecordReversal`
- `Core::Posting::Commands::PostEvent` for GL-backed events created by the preceding commands

The UI must show the account, source event or fee event, amount, business date, idempotency key, and expected effect before submission.

Any generic adjustment, new money movement, new `event_type`, new posting rule, new GL account mapping, or new reversal/return lifecycle requires a separate ADR.

---

## 4. Channel attribution

Phase 4.1 introduces a durable operational-event channel value `branch` for non-cash Branch HTML servicing actions.

Use channels as follows:

- `teller`: teller JSON and teller-cash activity that depends on teller session/drawer controls.
- `branch`: internal Branch HTML customer/account servicing that does not depend on teller cash drawer state.
- `api`: future external or service API calls, not internal browser CSR forms.
- `batch`: system-supervised batch processing.
- `system`: system-originated engine activity.

Branch CSR servicing must not reuse `teller` for non-cash actions merely because the screen lives in the Branch workspace. Keeping `branch` separate from `teller` preserves audit clarity: a fee waiver, account hold, or reversal performed from a customer-servicing screen is not the same operational channel as cash drawer activity.

Adding `branch` requires updating the operational-event channel allowlist and tests before exposing mutating Branch CSR forms.

---

## 5. Role gates

Phase 4.1 starts from the existing internal operator model in `Workspace::Models::Operator`.

Initial access posture:

- `teller`: may view customer/account search, account profile, balances, statement metadata, activity, and active holds.
- `teller`: may place routine holds only if the command captures `actor_id` and the UI does not bypass existing hold validations.
- `supervisor`: may perform teller permissions plus release holds, waive fees, reverse eligible events, and post the created GL-backed event where the workflow supports immediate posting.
- `operations` and `admin`: may receive read access only if support workflows need it; mutating access is not granted by default.

A dedicated `customer_service` role is deferred. Add it only if Branch tellers and CSRs need materially different permissions, navigation, or audit reporting.

Role values must be loaded from the database-backed operator row. Forms, params, headers, and hidden fields must never be trusted for role claims.

---

## 6. Audit requirements

Every Branch CSR write must leave durable audit evidence:

- `actor_id` from the authenticated internal operator
- channel `branch`
- idempotency key
- current open business date
- account id
- event id or referenced source event id
- amount and currency when applicable
- created/replay outcome
- posted event id and posting/journal identifiers when GL-backed

`PlaceHold` and `ReleaseHold` must accept and persist actor attribution before Branch CSR hold forms are treated as complete. Fee waivers and reversals already flow through operational events and posting, but the Branch controllers must pass the authenticated operator id.

Idempotency replays must be deterministic. A replay with the same key and different payload must fail rather than mutate or silently reinterpret an existing event.

Failures must render validation errors without partially created records. Posted history is immutable; corrections must be new events or existing compensating flows.

---

## 7. Non-goals

- Customer portal, customer authentication, self-service servicing, or customer-safe delivery rules.
- Partner, fintech, ACH, wire, card, ATM, or external API identity.
- Arbitrary ledger or account balance adjustments.
- New event types, posting rules, GL mappings, settlement accounts, or return/dispute lifecycles.
- Statement PDF rendering, document delivery, notifications, or delivery preferences.
- Full-text customer search, contact-center case management, task routing, or CRM workflows.
- Replacing or renaming existing JSON `/teller` routes.

---

## 8. Consequences

- CSR servicing can ship without creating another overlapping staff workspace.
- Branch becomes the staff surface for both teller workflows and customer/account servicing, with channel attribution distinguishing cash teller activity from non-cash servicing.
- The first implementation must update event channel validation and audit coverage before enabling mutating CSR forms.
- If a future contact-center model needs distinct navigation, staffing, or reporting, a separate `customer_service` workspace can be introduced later without changing domain ownership.

---

## 9. Implementation status

Phase 4.1 is implemented under the existing Branch HTML workspace:

- **Routes:** `GET /branch/customers`, `GET /branch/customers/:id`, `GET /branch/deposit_accounts/:id`, account-scoped activity, holds, statement metadata, and fee-waiver routes.
- **Read queries:** `Party::Queries::PartySearch`, `Accounts::Queries::DepositAccountsForParty`, `Accounts::Queries::DepositAccountProfile`, `Accounts::Queries::ListHoldsForAccount`, and `Deposits::Queries::ListDepositStatements`.
- **Guarded actions:** Branch CSR forms place/release holds, waive posted `fee.assessed` events with `fee.waived`, and record/post eligible `posting.reversal` events through existing commands.
- **Audit:** non-cash servicing events use channel `branch` and persist authenticated operator `actor_id`.
- **Tests:** `test/integration/branch_customer_servicing_test.rb` covers customer servicing access, channel/actor attribution, hold idempotency, fee-waiver posting, and reversal posting.

This implementation did not add a `customer_service` operator role. Branch tellers retain read/routine hold placement access; supervisors retain fee waiver, hold release, and reversal authority.
