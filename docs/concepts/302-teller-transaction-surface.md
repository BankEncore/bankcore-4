# Teller Transaction Surface in BankCORE

## Purpose

This concept defines where the teller transaction surface fits in BankCORE.

The Teller workspace is a controlled front-line execution surface. It lets staff initiate selected cash and account workflows, but it does not own financial truth, account state, product behavior, or physical custody by itself.

BankCORE's teller goal is operational sufficiency with strong controls:

- capture structured transaction intent
- enforce session, authority, product, balance, and posting controls
- create durable audit evidence
- post financial effects through the core posting path
- expose drawer/account impact clearly enough for branch staff to operate safely

This document is a planning and product-boundary artifact. It does not introduce new event types, posting rules, GL mappings, approval tables, receipt storage, or instrument lifecycle records by itself.

## Alignment with BankCORE implementation and roadmap

**Module mapping (see [module catalog](../architecture/bankcore-module-catalog.md)):** `Teller` owns teller session lifecycle and workstation-facing cash flows; `Branch` is the internal staff HTML workspace over teller and servicing commands; `Core::OperationalEvents` records durable business facts; `Core::Posting` converts eligible financial events into balanced journal entries; `Core::Ledger` stores financial truth; `Accounts` owns deposit account state, holds, restrictions, lifecycle, and available-balance checks; `Cash` owns vault/drawer custody locations, movements, counts, balances, and cash variances; `Products` / `Deposits` own product-driven deposit behavior; `Workspace` / `Organization` own operators, capabilities, and operating-unit scope.

**MVP vs broader scope:** Teller cash deposits, cash withdrawals, account transfers, manual fees, holds, reversals, teller sessions, drawer variance, trial balance, EOD readiness, and internal cash custody movements are MVP-aligned or already shipped in narrow slices. Check deposits, check cashing, official checks, loan payments, GL miscellaneous receipts, generalized approval queues, document-grade receipts, and external channel behavior are phased capabilities that require explicit ADR coverage before implementation.

**Staff authorized surfaces:** Branch HTML teller line, teller supervisor, CSR, and JSON `/teller` surfaces orchestrate access. They do not own domain state. Capability gates and operating-unit scope remain governed by [ADR-0029](../adr/0029-capability-first-authorization-layer.md), [ADR-0032](../adr/0032-operating-units-and-branch-scope.md), and [ADR-0037](../adr/0037-internal-staff-authorized-surfaces.md).

## Core Boundary Rules

1. Teller is an execution surface, not the financial kernel.
2. Controllers validate input, resolve actor/session/scope, and call domain commands. They must not build journal lines, mutate balances directly, or encode posting rules.
3. Material banking actions must create durable evidence: an `OperationalEvent`, a domain audit row, or a Cash custody record, depending on the owning domain.
4. Eligible financial events post through `Core::Posting` and persist balanced `journal_entries` / `journal_lines`.
5. Teller cash activity requires an open `TellerSession` when the cash-session policy is enabled.
6. Branch scope is `operating_unit_id`, not `branch_id`; operating units do not imply branch GL, branch business dates, or legal-entity separation.
7. Cash custody movement changes where cash is physically expected to be. It is not automatically a GL event.
8. Corrections are explicit forward records: reversals, releases, expirations, voids, replacements, superseding rows, or variance postings. Never silently edit posted history.

## Current MVP Surface

The current BankCORE teller/branch transaction surface should be treated as the MVP baseline.

| Teller activity | Primary owner | Evidence | Posting behavior | MVP posture |
| --- | --- | --- | --- | --- |
| Cash deposit to deposit account | `Core::OperationalEvents`, `Teller` | `deposit.accepted` | Dr `1110` / Cr `2110` | Shipped |
| Cash withdrawal | `Core::OperationalEvents`, `Accounts`, `Teller` | `withdrawal.posted` or `overdraft.nsf_denied` | Dr `2110` / Cr `1110`; NSF denial is no-GL plus possible fee | Shipped |
| Account-to-account transfer | `Core::OperationalEvents`, `Accounts` | `transfer.completed` or `overdraft.nsf_denied` | Dr source `2110` / Cr destination `2110` | Shipped |
| Manual fee assessment | `Core::OperationalEvents`, `Core::Posting` | `fee.assessed` | Dr `2110` / Cr fee income | Shipped |
| Fee waiver | `Core::OperationalEvents`, `Core::Posting` | `fee.waived` | Dr fee income / Cr `2110` | Shipped |
| Place hold | `Accounts` | `hold.placed` | No GL | Shipped |
| Release or expire hold | `Accounts` | `hold.released` | No GL | Shipped |
| Reverse posted financial event | `Core::OperationalEvents`, `Core::Posting` | `posting.reversal` | Equal/opposite posting | Shipped |
| Open / close teller session | `Teller` | `teller_sessions` row | No GL by default | Shipped |
| Approve teller variance | `Teller` | session variance approval; optional `teller.drawer.variance.posted` | Optional GL `1110` / `5190` | Shipped |
| Vault-to-drawer / drawer-to-vault transfer | `Cash` | `cash_movement`, optional `cash.movement.completed` | No GL for internal custody movement | Shipped foundation |
| Cash count / cash variance | `Cash` | `cash_count`, `cash_variance` | GL only for approved `cash.variance.posted` | Shipped foundation |

## MVP Acceptance Matrix

Use this matrix to decide whether a teller-facing change belongs in the MVP transaction surface or should be planned as a later slice.

| Activity | MVP classification | Command / controller surface | Durable evidence | Acceptance proof |
| --- | --- | --- | --- | --- |
| Cash deposit | MVP / shipped | `Branch::DepositsController`, `Teller::OperationalEventsController`, `Core::OperationalEvents::Commands::RecordEvent`, `Core::Posting::Commands::PostEvent` | `deposit.accepted`, posting batch, journal entry | Branch form can record-only and record-and-post; open teller session is required where configured; journal posts Dr `1110` / Cr `2110` |
| Cash withdrawal | MVP / shipped | `Branch::WithdrawalsController`, `Accounts::Commands::AuthorizeDebit`, `Core::Posting::Commands::PostEvent` | `withdrawal.posted` or `overdraft.nsf_denied`; optional NSF fee event | Branch form can record-and-post; insufficient funds produces NSF denial evidence instead of an invalid withdrawal |
| Account transfer | MVP / shipped | `Branch::TransfersController`, `Accounts::Commands::AuthorizeDebit`, `Core::Posting::Commands::PostEvent` | `transfer.completed` or `overdraft.nsf_denied` | Transfer posts balanced source/destination `2110` legs; insufficient funds follows the same NSF denial path as withdrawals |
| Manual fee assessment | MVP / shipped | `Core::OperationalEvents::Commands::RecordEvent`, `Core::Posting::Commands::PostEvent`; Branch/JSON event entry surfaces | `fee.assessed` | Fee event records and posts separately from the customer transaction that triggered it |
| Fee waiver | MVP / shipped | Branch fee waiver surface, `Core::OperationalEvents::Commands::RecordEvent`, `Core::Posting::Commands::PostEvent` | `fee.waived` linked to prior posted fee | Supervisor/capability-gated waiver posts compensating fee-income/account legs |
| Hold placement | MVP / shipped | Branch account hold surface, JSON `/teller/holds`, `Accounts::Commands::PlaceHold` | `hold.placed` and `holds` row | Hold is account-scoped, idempotent, no-GL, and visible on account/hold reads |
| Hold release or expiration | MVP / shipped | Branch account hold release surface, JSON `/teller/holds/release`, `Accounts::Commands::ReleaseHold`, `Accounts::Commands::ExpireDueHolds` | `hold.released` and updated `holds` row | Active hold can be released through a controlled surface; release remains no-GL |
| Reversal | MVP / shipped | Branch/JSON reversal surfaces, `Core::OperationalEvents::Commands::RecordReversal`, `Core::Posting::Commands::PostEvent` | `posting.reversal` with `reversal_of_event_id` / `reversed_by_event_id` linkage | Eligible posted event creates a new reversal event and equal/opposite journal; guarded events are rejected |
| Teller session open | MVP / shipped | Branch/JSON teller session surfaces, `Teller::Commands::OpenSession` | `teller_sessions` row, Cash drawer linkage where resolved | Operator can open one active drawer/session in the operating unit; session can resolve a `teller_drawer` Cash location |
| Teller session close | MVP / shipped | Branch/JSON teller session close surfaces, `Teller::Commands::CloseSession` | closed or `pending_supervisor` teller session; optional drawer variance event | Expected vs actual cash is captured; configured variance threshold routes to supervisor approval |
| Teller variance approval | MVP / shipped | Branch/Ops/JSON variance approval surfaces, `Teller::Commands::ApproveSessionVariance` | supervisor fields on `teller_sessions`; optional `teller.drawer.variance.posted` | Supervisor approval completes pending variance; optional GL posting occurs only when enabled |
| Vault-to-drawer / drawer-to-vault transfer | MVP-adjacent cash foundation / shipped | Branch/JSON Cash transfer surfaces, `Cash::Commands::TransferCash`, `Cash::Commands::ApproveCashMovement` | `cash_movements`, `cash.movement.completed` where recorded, `cash_balances` projection | Internal custody move updates Cash balances and approval state; ordinary internal transfer creates no journal entry |
| Cash count | MVP-adjacent cash foundation / shipped | Branch/JSON Cash count surfaces, `Cash::Commands::RecordCashCount` | `cash_counts`; `cash_variances` when counted amount differs | Count preserves expected vs counted amount and creates variance evidence without silently editing history |
| Cash variance approval | MVP-adjacent cash foundation / shipped | Ops/JSON Cash variance approval surfaces, `Cash::Commands::ApproveCashVariance` | `cash_variance.posted` event and journal when approved | Approved variance posts GL adjustment through `Core::Posting`; no-self-approval and state guards apply |
| Trial balance / EOD readiness | MVP / shipped | JSON reports, Ops EOD/close package surfaces, `Teller::Queries::EodReadiness`, `Core::Ledger::Queries::TrialBalanceForBusinessDate` | read-only readiness and trial-balance evidence | Readiness exposes pending events, open sessions, trial-balance status, and close evidence without mutating financial truth |

Items not listed above are not part of the teller MVP unless a follow-up ADR explicitly pulls them forward. In particular, check deposits, check cashing, official checks, loan payments, GL miscellaneous receipts, generalized approval queues, durable receipt documents, and denomination-level drawer tickets remain later slices.

## Near-Term Teller UI Capabilities

These are BankCORE-aligned UI/read-model capabilities over the shipped foundation. They should not change posting semantics by themselves.

### Structured Input

Each teller transaction form should capture only the fields required by the underlying command:

- account lookup by account number, customer search, or selected customer context
- transaction type
- amount in minor units
- currency
- teller session
- memo or reason where the domain command requires it
- reference number or support key where useful
- idempotency key, generated by the client or controller
- person served, when different from the account owner, as audit context once a domain field or support payload is accepted

`person_served` is useful operational context, but it should not imply ownership, authority, KYC, or signer rights without an Accounts/Party authority model.

### Real-Time Summary Panel

The teller UI should show a persistent preview panel for cash/account impact:

- transaction type
- total cash in
- total cash out
- fees
- net cash impact
- projected teller expected drawer cash
- projected account available balance where applicable
- warnings and approval requirements

This panel is a preview/read model. It must not become a second source of truth. Final balances and journals come from committed operational events and posting.

### Holds and Availability

MVP-lite funds availability is manual and bounded:

- branch staff can place a hold on deposited funds
- amount, expiration date, reason code, and description are captured where supported
- automated Reg CC and collected-funds scheduling remains deferred

### Fee Handling

The teller surface may offer manual fee assessment and fee waiver flows using existing `fee.assessed` and `fee.waived` events.

Per-transaction automatic fee prompts can be previewed later from product rules, but product configuration decides eligibility and `Core::Posting` decides accounting. Teller screens should not hardcode fee rules or GL treatment.

### Receipt and Trace Evidence

After commit, the teller surface should expose trace evidence:

- transaction type
- business date and timestamp
- operator / teller
- account number or masked account summary
- amount
- fee amount if applicable
- operational event id
- posting batch / journal trace where applicable
- reference or idempotency key

Receipt display and simple reprint are reasonable near-term UI features. Durable printable receipt artifacts, delivery, retention, and document storage belong to a later `Documents` / `Reporting` slice.

## Supervisor Controls

BankCORE already supports command-specific supervisor and capability gates. Teller UI should surface those gates clearly.

Near-term controls:

- block actions when required approval is missing
- show warnings when approval may be required
- record approving actor, approval timestamp, and reason where the owning command supports it
- enforce no-self-approval in Cash and variance workflows where policy requires it

Generalized approval queues, maker-checker tables, approval expiration, delegation, and queue assignment belong to `Workflow` and require a dedicated slice.

Inline supervisor credential prompts may be a UX option, but they should not be the architectural source of approval truth.

## Search and Retrieval

The teller surface should provide minimal retrieval over existing read models:

- session-scoped recent transactions
- today's teller activity
- account activity lookup
- operational event detail
- receipt or trace reprint where supported
- filters by account, event type, reference id, idempotency key, and session where available

Ops-oriented investigation, broad event search, close packages, and exception review remain better suited to the Ops workspace.

## Post-MVP / Requires ADR

The following capabilities are legitimate banking needs, but they veer beyond BankCORE's current teller MVP. They should not be folded into Teller without explicit ownership, event, posting, and control decisions.

| Capability | Likely owner | Why it is not teller MVP |
| --- | --- | --- |
| Check deposit, on-us or transit | `Integration`, `Accounts`, possibly future item-processing domain | Requires item lifecycle, availability rules, returns, collection risk, and check metadata |
| Check cashing | future `Instruments` or check domain, `Cash`, `Core::Posting` | Requires presenter authority, check item lifecycle, limits, returns, and cash payout risk |
| Official check / bank draft issuance | future `Instruments` | Requires instrument records, liability account, issue/void/paid/replacement lifecycle, reconciliation |
| Loan payment | `Loans`, `Core::Posting` | Requires loan servicing, amortization, allocation, delinquency, and loan GL rules |
| GL miscellaneous receipt | `Core::Ledger` plus a controlled Operations/Admin surface | Non-account GL intake is high-risk and should not be a generic teller shortcut |
| Multi-check deposit ticket | item-processing domain plus `Integration` | Requires item detail, balancing, holds, return handling, and operational proofing |
| Full approval queue | `Workflow` | Requires durable approval request/decision model beyond command-specific gates |
| Document-grade receipt storage | `Documents`, `Reporting` | Requires retention, rendering, storage, reprint policy, and audit rules |
| Denomination-level drawer activity | `Cash` | Requires denomination models for movements/counts and reconciliation |
| ATM, recycler, night drop teller flows | `Cash`, `Integration` | Requires device/location lifecycle and settlement/exception handling |

## Worked Examples

### Cash Withdrawal

Input:

```json
{
  "event_type": "withdrawal.posted",
  "source_account_id": 123,
  "amount_minor_units": 5000,
  "currency": "USD",
  "channel": "teller",
  "teller_session_id": 45,
  "idempotency_key": "branch-main:teller-9:session-45:withdrawal:abc123"
}
```

Command flow:

1. Resolve operator, teller session, and `operating_unit_id`.
2. Validate the session is open and belongs to an active teller drawer where policy requires it.
3. Run `Accounts::Commands::AuthorizeDebit` for available-balance and overdraft policy.
4. Record `withdrawal.posted` through `Core::OperationalEvents`.
5. Post through `Core::Posting`.
6. Expose event, posting batch, journal, and teller-session evidence to the UI.

Posting outline:

```text
Dr 2110 Customer Deposits Payable
Cr 1110 Cash and Cash Items
```

Teller drawer effect:

```text
Expected drawer cash decreases by 5000 minor units.
```

The drawer expected amount is derived from teller-session cash events. Physical custody remains tied to the teller drawer Cash location; any later count difference is handled as a teller or Cash variance, not by editing the withdrawal.

### Vault-to-Drawer Cash Transfer

Input:

```json
{
  "source_cash_location_id": 10,
  "destination_cash_location_id": 22,
  "amount_minor_units": 200000,
  "currency": "USD",
  "movement_type": "vault_to_drawer",
  "business_date": "2026-04-30",
  "idempotency_key": "cash-transfer:main-vault:drawer-22:2026-04-30:001"
}
```

Command flow:

1. Resolve operator and operating unit.
2. Validate both Cash locations are active, same currency, and allowed for the movement.
3. Require approval for vault-involved movement according to Cash policy.
4. Enforce no-self-approval where applicable.
5. Complete the custody movement and update rebuildable `cash_balances`.
6. Record no-GL custody evidence, such as `cash.movement.completed`, where the command does so.

Posting outline:

```text
No journal entry for ordinary internal custody movement.
```

Custody effect:

```text
Branch vault custody balance decreases.
Teller drawer custody balance increases.
Institutional GL cash does not change.
```

## ADR Triggers

Create or update an ADR before implementing any teller surface slice that:

- adds a new GL-backed event type
- adds a new instrument, check, loan, external rail, or item-processing lifecycle
- changes reversal, void, replacement, return, or correction semantics
- introduces a generalized `Workflow` approval model
- adds per-product GL mapping or product behavior source-of-truth changes
- creates durable receipt/document artifacts
- changes branch business-date, branch GL, or multi-entity accounting behavior

## Suggested Summary

BankCORE should treat Teller as a controlled transaction entry surface, not a catch-all banking operations module. The MVP teller surface covers cash deposits, cash withdrawals, account transfers, manual fees and waivers, holds, controlled reversals, teller sessions, drawer variance, receipt/trace evidence, and initiation of internal cash custody movements. The system guarantee is that financial impact flows through operational events and balanced posting, while physical cash custody flows through Cash locations and movements.

Check deposits, check cashing, official checks, loan payments, miscellaneous GL receipts, generalized approval queues, denomination-level activity, and document-grade receipts are valid future capabilities, but they belong to later domain-owned slices with explicit ADR coverage.
