# Teller Transaction Surface in BankCORE

## Purpose

This concept defines where the **teller-adjacent execution surface** fits in BankCORE: JSON **`/teller`** and the Branch **teller line** (and supervisor approvals tied to those flows). It is **not** the full bank capability universe—many families run on **`batch`**, **`system`**, or **Ops** surfaces ([ADR-0037](../adr/0037-internal-staff-authorized-surfaces.md)).

The Teller workspace is a controlled front-line execution surface. It lets staff initiate selected cash and account workflows, but it does not own financial truth, account state, product behavior, or physical custody by itself.

BankCORE's teller goal is operational sufficiency with strong controls:

- capture structured transaction intent
- enforce session, authority, product, balance, and posting controls
- create durable audit evidence
- post financial effects through the core posting path
- expose drawer/account impact clearly enough for branch staff to operate safely

This document is a planning and product-boundary artifact. It does not introduce new event types, posting rules, GL mappings, approval tables, receipt storage, or instrument lifecycle records by itself.

For the **bank-wide capability taxonomy** (families **F1–F17**, phased **T1–T4** slices, and channel-vs-family framing), see [303-bank-transaction-capability-taxonomy.md](303-bank-transaction-capability-taxonomy.md).

### Relationship to capability taxonomy

**Lanes vs domains:** Branch CSR servicing, teller cash, supervisor approvals, JSON **`/teller`**, and batch/system jobs are **surfaces** and **`operational_events.channel`** producers—not capability families. The durable fact still lands as an **`OperationalEvent`** (plus domain-owned rows such as **`Cash`** movements) regardless of lane ([ADR-0037](../adr/0037-internal-staff-authorized-surfaces.md)). **Teller** (the module) orchestrates sessions and workstation rules; **303** places each activity in an **F-family** for ownership and sequencing.

## Alignment with BankCORE implementation and roadmap

**Module mapping (see [module catalog](../architecture/bankcore-module-catalog.md)):** `Teller` owns teller session lifecycle and workstation-facing cash flows; `Branch` is the internal staff HTML workspace over teller and servicing commands; `Core::OperationalEvents` records durable business facts; `Core::Posting` converts eligible financial events into balanced journal entries; `Core::Ledger` stores financial truth; `Accounts` owns deposit account state, holds, restrictions, lifecycle, and available-balance checks; `Cash` owns vault/drawer custody locations, movements, counts, balances, and cash variances; `Products` / `Deposits` own product-driven deposit behavior; `Workspace` / `Organization` own operators, capabilities, and operating-unit scope.

**MVP vs broader scope:** Teller cash deposits, accepted check deposits, combined cash/check deposit tickets, cash withdrawals, account transfers, manual fees, holds, reversals, teller sessions, drawer variance, trial balance, EOD readiness, and internal cash custody movements are MVP-aligned or already shipped in narrow slices. Check cashing, check clearing/returns, official checks, loan payments, GL miscellaneous receipts, generalized approval queues, document-grade receipts, and external channel behavior are phased capabilities that require explicit ADR coverage before implementation.

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

### Customer transaction surface[1]

| Teller activity | Primary owner | Evidence | Posting behavior | MVP posture |
| --- | --- | --- | --- | --- |
| Cash deposit to deposit account | `Core::OperationalEvents`, `Teller` | `deposit.accepted` | Dr `1110` / Cr `2110` | Shipped |
| Check deposit to deposit account | `Core::OperationalEvents`, `Accounts`, `Teller` | `check.deposit.accepted`; optional linked hold | Dr `1160` / Cr `2110`; no drawer cash delta | Shipped |
| Combined cash/check deposit ticket | `Core::OperationalEvents`, `Accounts`, `Teller` | Grouped `deposit.accepted` and/or `check.deposit.accepted`; optional check hold | Cash posts Dr `1110` / Cr `2110`; checks post Dr `1160` / Cr `2110` | Shipped |
| Cash withdrawal | `Core::OperationalEvents`, `Accounts`, `Teller` | `withdrawal.posted` or `overdraft.nsf_denied` | Dr `2110` / Cr `1110`; NSF denial is no-GL plus possible fee | Shipped |
| Account-to-account transfer | `Core::OperationalEvents`, `Accounts` | `transfer.completed` or `overdraft.nsf_denied` | Dr source `2110` / Cr destination `2110` | Shipped |
| Manual fee assessment | `Core::OperationalEvents`, `Core::Posting` | `fee.assessed` | Dr `2110` / Cr fee income | Shipped |
| Fee waiver | `Core::OperationalEvents`, `Core::Posting` | `fee.waived` | Dr fee income / Cr `2110` | Shipped |
| Place hold | `Accounts` | `hold.placed` | No GL | Shipped |
| Release or expire hold | `Accounts` | `hold.released` | No GL | Shipped |
| Reverse posted financial event | `Core::OperationalEvents`, `Core::Posting` | `posting.reversal` | Equal/opposite posting | Shipped |
| Open / close teller session | `Teller` | `teller_sessions` row | No GL by default | Shipped |
| Approve teller variance | `Teller` | session variance approval; optional `teller.drawer.variance.posted` | Optional GL `1110` / `5190` | Shipped |

### Teller-adjacent cash custody controls[1]

These controls are teller-adjacent because branch staff use them and they affect close readiness, but they remain Cash-domain custody workflows rather than customer transaction families.

| Teller-adjacent activity | Primary owner | Evidence | Posting behavior | MVP posture |
| --- | --- | --- | --- | --- |
| Vault-to-drawer / drawer-to-vault transfer | `Cash` | `cash_movement`, optional `cash.movement.completed` | No GL for internal custody movement | Shipped foundation |
| Cash count / cash variance | `Cash` | `cash_count`, `cash_variance` | GL only for approved `cash.variance.posted` | Shipped foundation |

## MVP Acceptance Matrix

Use this matrix to decide whether a teller-facing change belongs in the MVP transaction surface or should be planned as a later slice.

| Activity | MVP classification | Command / controller surface | Durable evidence | Acceptance proof |
| --- | --- | --- | --- | --- |
| Cash deposit | MVP / shipped | `Branch::DepositsController`, `Teller::OperationalEventsController`, `Core::OperationalEvents::Commands::RecordEvent`, `Core::Posting::Commands::PostEvent` | `deposit.accepted`, posting batch, journal entry | Branch form can record-only and record-and-post; open teller session is required where configured; journal posts Dr `1110` / Cr `2110`; posting applies drawer custody delta for session-linked teller cash per [ADR-0039](../adr/0039-teller-session-drawer-custody-projection.md) |
| Check deposit | MVP / shipped | `Branch::CheckDepositsController`, `Teller::OperationalEventsController`, `Core::OperationalEvents::Commands::AcceptCheckDeposit` | `check.deposit.accepted`, posting batch, journal entry, optional linked hold | Branch form accepts one or more structured check items; JSON accepts structured and legacy item payloads; journal posts Dr `1160` / Cr `2110`; optional event-level holds constrain availability; no teller drawer cash delta ([ADR-0040](../adr/0040-check-deposit-vertical-slice.md)) |
| Combined deposit ticket | MVP / shipped | `Branch::DepositTicketsController`, `Core::OperationalEvents::Commands::AcceptDepositTicket` | Shared-reference `deposit.accepted` and/or `check.deposit.accepted`, posting batches, journal entries, optional linked hold | Branch form accepts cash and/or check items in one operation; server transaction rolls back all child work if any portion fails; child events preserve cash drawer and check clearing semantics ([ADR-0043](../adr/0043-combined-cash-check-deposit-workflow.md)) |
| Cash withdrawal | MVP / shipped | `Branch::WithdrawalsController`, `Accounts::Commands::AuthorizeDebit`, `Core::Posting::Commands::PostEvent` | `withdrawal.posted` or `overdraft.nsf_denied`; optional NSF fee event | Branch form can record-and-post; insufficient funds produces NSF denial evidence instead of an invalid withdrawal; posting applies drawer custody delta for session-linked teller cash per [ADR-0039](../adr/0039-teller-session-drawer-custody-projection.md) |
| Account transfer | MVP / shipped | `Branch::TransfersController`, `Accounts::Commands::AuthorizeDebit`, `Core::Posting::Commands::PostEvent` | `transfer.completed` or `overdraft.nsf_denied` | Transfer posts balanced source/destination `2110` legs; insufficient funds follows the same NSF denial path as withdrawals |
| Manual fee assessment | MVP / shipped | `Core::OperationalEvents::Commands::RecordEvent`, `Core::Posting::Commands::PostEvent`; Branch/JSON event entry surfaces | `fee.assessed` | Fee event records and posts separately from the customer transaction that triggered it |
| Fee waiver | MVP / shipped | Branch fee waiver surface, `Core::OperationalEvents::Commands::RecordEvent`, `Core::Posting::Commands::PostEvent` | `fee.waived` linked to prior posted fee | Supervisor/capability-gated waiver posts compensating fee-income/account legs |
| Hold placement | MVP / shipped | Branch account hold surface, JSON `/teller/holds`, `Accounts::Commands::PlaceHold` | `hold.placed` and `holds` row | Hold is account-scoped, idempotent, no-GL, and visible on account/hold reads |
| Hold release or expiration | MVP / shipped | Branch account hold release surface, JSON `/teller/holds/release`, `Accounts::Commands::ReleaseHold`, `Accounts::Commands::ExpireDueHolds` | `hold.released` and updated `holds` row | Active hold can be released through a controlled surface; release remains no-GL |
| Reversal | MVP / shipped | Branch/JSON reversal surfaces, `Core::OperationalEvents::Commands::RecordReversal`, `Core::Posting::Commands::PostEvent` | `posting.reversal` with `reversal_of_event_id` / `reversed_by_event_id` linkage | Eligible posted event creates a new reversal event and equal/opposite journal; guarded events are rejected |
| Teller session open | MVP / shipped | Branch/JSON teller session surfaces, `Teller::Commands::OpenSession` | `teller_sessions` row, Cash drawer linkage where resolved | Operator can open one active drawer/session in the operating unit; session can resolve a `teller_drawer` Cash location |
| Teller session close | MVP / shipped | Branch/JSON teller session close surfaces, `Teller::Commands::CloseSession` | closed or `pending_supervisor` teller session; optional drawer variance event | Expected cash is computed server-side; operators supply actual count only; variance threshold routes to supervisor approval ([ADR-0039](../adr/0039-teller-session-drawer-custody-projection.md)) |
| Teller variance approval | MVP / shipped | Branch/Ops/JSON variance approval surfaces, `Teller::Commands::ApproveSessionVariance` | supervisor fields on `teller_sessions`; optional `teller.drawer.variance.posted` | Supervisor approval completes pending variance; optional GL posting occurs only when enabled |
| Vault-to-drawer / drawer-to-vault transfer | MVP-adjacent cash foundation / shipped | Branch/JSON Cash transfer surfaces, `Cash::Commands::TransferCash`, `Cash::Commands::ApproveCashMovement` | `cash_movements`, `cash.movement.completed` where recorded, `cash_balances` projection | Internal custody move updates Cash balances and approval state; optional **`teller_session_id`** ties completed movements to session expected cash when supplied ([ADR-0039](../adr/0039-teller-session-drawer-custody-projection.md)); ordinary internal transfer creates no journal entry |
| Cash count | MVP-adjacent cash foundation / shipped | Branch/JSON Cash count surfaces, `Cash::Commands::RecordCashCount` | `cash_counts`; `cash_variances` when counted amount differs | Count preserves expected vs counted amount and creates variance evidence without silently editing history |
| Cash variance approval | MVP-adjacent cash foundation / shipped | Ops/JSON Cash variance approval surfaces, `Cash::Commands::ApproveCashVariance` | `cash_variance.posted` event and journal when approved | Approved variance posts GL adjustment through `Core::Posting`; no-self-approval and state guards apply |
| Trial balance / EOD readiness | MVP / shipped | JSON reports, Ops EOD/close package surfaces, `Teller::Queries::EodReadiness`, `Core::Ledger::Queries::TrialBalanceForBusinessDate` | read-only readiness and trial-balance evidence | Readiness exposes pending events, open sessions, trial-balance status, and close evidence without mutating financial truth |

Items not listed above are not part of the teller MVP unless a follow-up ADR explicitly pulls them forward. In particular, check cashing, check clearing/returns, official checks, loan payments, GL miscellaneous receipts, generalized approval queues, durable receipt documents, and denomination-level drawer tickets remain later slices.

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

### Standard Form Envelope

The Branch HTML forms and JSON `/teller` requests should keep a predictable shape without forcing every transaction into one generic model. Each form should have:

1. A **common control envelope** for actor/session/idempotency behavior.
2. A **transaction-specific payload** for account, event, hold, or Cash fields.
3. A **result envelope** that exposes durable trace evidence after commit.

The common control envelope is:

| Field | Required | Applies to | Notes |
| --- | --- | --- | --- |
| `idempotency_key` | Yes | All state-changing teller/branch forms | Stable across retries for the same intended action |
| `amount_minor_units` | Yes for monetary forms | Customer money movement, fees, holds, Cash movement/count variance inputs | Amounts remain integer minor units |
| `currency` | Yes for monetary forms | Customer money movement and Cash forms | Current MVP is USD, but currency stays explicit |
| `teller_session_id` | Yes for teller cash activity when policy requires it | Cash deposit, cash withdrawal | Not required for account-to-account transfer or non-cash Branch servicing |
| `record_and_post` | Optional | Financial operational-event forms | Allows record-only review or immediate posting; not used for Cash custody commands |
| `reference_id` / memo / reason | Optional unless command requires it | Fees, holds, reversals, servicing actions, future receipts | Support context only; should not drive posting rules |
| `operating_unit_id` | Usually resolved, not user-entered | Staff-originated actions | Resolve from current operator/session/scope; do not expose as routine teller input |
| `actor_id` | Resolved, not user-entered | All staff actions | Comes from current operator or `X-Operator-Id` |
| `channel` | Resolved, not user-entered for Branch forms | Branch HTML and JSON `/teller` | Branch HTML may intentionally record teller-channel cash events; controllers own that choice |

Transaction-specific payloads should stay narrow:

| Form family | Scope key | Required payload | Existing surface |
| --- | --- | --- | --- |
| Cash deposit | `deposit` | `deposit_account_id`, `amount_minor_units`, `currency`, `teller_session_id`, `idempotency_key`, optional `record_and_post` | `Branch::DepositsController`; JSON `/teller/operational_events` |
| Cash withdrawal | `withdrawal` | `deposit_account_id`, `amount_minor_units`, `currency`, `teller_session_id`, `idempotency_key`, optional `record_and_post` | `Branch::WithdrawalsController`; JSON `/teller/operational_events` |
| Account transfer | `transfer` | `source_account_id`, `destination_account_id`, `amount_minor_units`, `currency`, `idempotency_key`, optional `record_and_post` | `Branch::TransfersController`; JSON `/teller/operational_events` |
| Hold placement | `hold` / account hold form | `deposit_account_id`, `amount_minor_units`, `currency`, hold type/reason/expiration where supported, `idempotency_key` | Branch hold surfaces; JSON `/teller/holds` |
| Hold release | `hold_release` | `hold_id`, `idempotency_key` | Branch hold release surfaces; JSON `/teller/holds/release` |
| Reversal | `reversal` | original event id, reason/reference where supported, `idempotency_key` | Branch/JSON reversal surfaces |
| Teller session open | `teller_session` | `drawer_code` where supplied | Branch/JSON teller session surfaces |
| Teller session close | `teller_session_close` | `teller_session_id`, `actual_cash_minor_units` or equivalent close count fields; expected cash is **not** a trusted client input | Branch/JSON teller session close surfaces |
| Cash movement | `cash_transfer` | `source_cash_location_id`, `destination_cash_location_id`, `amount_minor_units`, `reason_code`, `idempotency_key`, optional `teller_session_id` when the movement should affect that session’s expected cash | Branch/JSON Cash transfer surfaces |
| Cash count | `cash_count` | `cash_location_id`, `counted_amount_minor_units`, optional `expected_amount_minor_units`, `idempotency_key` | Branch/JSON Cash count surfaces |

The result envelope should be consistent even when the underlying command differs:

| Result field | Meaning |
| --- | --- |
| `outcome` | Created, replayed, posted, denied, pending approval, or similar command outcome |
| `operational_event_id` | Present when an operational event is recorded |
| `event_type` / `event_status` | Event identity and lifecycle status |
| `posting_batch_ids` / `journal_entry_ids` | Present when the event has posted |
| `cash_movement_id` / `cash_count_id` / `cash_variance_id` | Present for Cash custody workflows |
| `business_date` | Operational business date used by the command |
| `teller_session_id` | Present for session-bound teller cash activity |
| `operating_unit_id` | Resolved branch/operating-unit scope |
| `idempotency_key` | Retry trace |
| `warnings` / `errors` | Human-readable blocking errors or non-blocking warnings |

This envelope should standardize UI behavior and tests, not create a new persistence table. Domain commands remain the write boundary.

### Real-Time Summary Panel

The teller UI should show a persistent preview panel for cash/account impact. This panel helps the operator understand what will happen before submit, but it is not a posting engine and must not become a second balance source.

Preview inputs should come from existing read-side contracts:

| Preview source | Existing owner | Use in panel |
| --- | --- | --- |
| Teller session status and drawer linkage | `Teller::Models::TellerSession`, `Teller::Queries::BranchSessionDashboard` | Confirm the operator has an open session and identify the active drawer/session context |
| Expected drawer cash | `Teller::Queries::ExpectedCashForSession` | Show current expected cash and projected expected cash after a deposit or withdrawal |
| Deposit account available balance | `Accounts::Services::AvailableBalanceMinorUnits` | Show current and projected available balance for withdrawals/transfers where an account is selected |
| Cash location balance | `Cash::Queries::CashPosition` | Show vault/drawer custody balance for Cash movement forms |
| Operational event metadata | `Core::OperationalEvents::EventCatalog` | Explain whether the selected transaction is financial, reversible, teller-channel, or no-GL |

The panel should show:

- transaction type
- selected account or account pair
- selected teller session and drawer where applicable
- total cash in
- total cash out
- fees, if the current form explicitly includes them
- net cash impact
- current expected drawer cash
- projected expected drawer cash
- current account available balance
- projected account available balance where applicable
- current source/destination Cash location balance for custody movements
- warnings and approval requirements

Recommended preview calculations:

| Transaction family | Drawer preview | Account preview | Custody preview |
| --- | --- | --- | --- |
| Cash deposit | `expected_drawer_cash + amount` | `available_balance + amount`, before optional holds | No Cash custody projection unless drawer location balance is shown separately |
| Cash withdrawal | `expected_drawer_cash - amount` | `available_balance - amount` | Warn if drawer custody balance would be insufficient, if policy enforces that |
| Account transfer | No drawer impact | Source `available_balance - amount`; destination balance may increase after posting | No custody impact |
| Hold placement | No drawer impact | `available_balance - hold_amount` | No custody impact |
| Fee assessment | Usually no drawer impact if account-funded | `available_balance - fee_amount` | No custody impact |
| Fee waiver | No drawer impact | `available_balance + waived_amount` | No custody impact |
| Vault-to-drawer transfer | No customer account impact | No account impact | Source location decreases; destination location increases |
| Drawer-to-vault transfer | No customer account impact | No account impact | Source location decreases; destination location increases |

Warnings should be explicit but conservative:

- `blocking`: no open teller session for teller cash transaction
- `blocking`: selected session is not open
- `blocking`: account is closed, restricted, or not eligible for the requested command
- `blocking`: insufficient available balance for withdrawal or transfer unless product policy allows denial/fee flow
- `blocking`: approval required but current actor lacks capability
- `blocking`: Cash movement source location lacks sufficient custody balance, where Cash policy enforces it
- `warning`: transaction may create NSF denial and fee
- `warning`: transaction exceeds a configured teller/cash movement threshold
- `warning`: record-only mode will leave a pending event until explicitly posted
- `warning`: projected values may change if another event posts before submit

The preview is intentionally non-authoritative. Final behavior is determined inside the command transaction:

1. Re-read current account/session/cash state.
2. Enforce command-level guards and capability checks.
3. Record the operational event, audit row, or Cash custody record.
4. Post through `Core::Posting` where applicable.
5. Return committed trace evidence for the result envelope.

Do not persist preview rows, pre-reserve funds, or treat preview output as a posting promise in the MVP. If later product scope requires reservation, quote locks, denomination-level cash proofing, or formal approval pre-checks, that should be a separate ADR-backed slice.

### Holds and Availability

MVP-lite funds availability is manual and bounded:

- branch staff can place a hold on deposited funds
- amount, expiration date, reason code, and description are captured where supported
- automated collected-funds scheduling, Reg CC policy automation, and item-level funds-availability workflows remain deferred[2]

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

## Footnotes

[1] Split the MVP table into `customer transaction surface` and `teller-adjacent cash custody controls` to match the ownership boundary already defined in ADR-0039: teller sessions and customer financial events are distinct from Cash-owned custody state, even when both appear on the branch/teller line.

[2] Tightened the availability wording so this concept doc does not imply that check/item availability policy has already been chosen. Existing shipped behavior is still manual hold placement; automated Reg CC-style scheduling and item-level availability remain ADR-gated future work.

Near-term controls:

- block actions when required approval is missing
- show warnings when approval may be required
- record approving actor, approval timestamp, and reason where the owning command supports it
- enforce no-self-approval in Cash and variance workflows where policy requires it

Generalized approval queues, maker-checker tables, approval expiration, delegation, and queue assignment belong to `Workflow` and require a dedicated slice.

Inline supervisor credential prompts may be a UX option, but they should not be the architectural source of approval truth.

### Control Ownership Matrix

MVP controls should stay with the domain that owns the risk. Teller and Branch screens show the decision, but the command enforces it.

| Control | Owning module / command | Capability or guard | MVP behavior |
| --- | --- | --- | --- |
| Teller cash session required | `Core::OperationalEvents::Commands::RecordEvent`, `Teller::Commands::OpenSession` | Open `teller_sessions` row; `TELLER_REQUIRE_OPEN_SESSION_FOR_CASH` policy | Cash deposits and withdrawals are blocked without an open teller session when policy is enabled |
| Debit authorization | `Accounts::Commands::AuthorizeDebit` | Available balance, active holds, restrictions, overdraft policy | Withdrawal/transfer either records the requested event or records `overdraft.nsf_denied` with fee evidence where policy requires |
| Account restriction and close guards | `Accounts` commands and services | Account status, active restrictions, pending events, active holds | Restricted or closed accounts are rejected by command-level rules, not by UI-only checks |
| Manual hold placement | `Accounts::Commands::PlaceHold` | `hold.place`; account and amount validation | Hold is no-GL, account-scoped, idempotent, and visible in hold/account reads |
| Hold release | `Accounts::Commands::ReleaseHold` | `hold.release` | Release is supervisor/capability-gated and remains no-GL |
| Fee waiver | `Core::OperationalEvents`, `Core::Posting`, Branch fee waiver surface | `fee.waive`; prior posted fee match | Waiver posts as its own financial event and does not mutate the original fee |
| Reversal | `Core::OperationalEvents::Commands::RecordReversal`, `Core::Posting::Commands::PostEvent` | `reversal.create`; event-type reversibility; hold guards | Reversal creates a new linked `posting.reversal` and equal/opposite journal when allowed |
| Teller session variance | `Teller::Commands::CloseSession`, `Teller::Commands::ApproveSessionVariance` | `teller_session_variance.approve`; configured variance threshold | Close goes to `pending_supervisor` when variance exceeds threshold; supervisor approval completes it |
| Optional teller drawer variance GL | `Teller::Services::PostDrawerVarianceToGl`, `Core::Posting` | `TELLER_POST_DRAWER_VARIANCE_TO_GL` | GL posting occurs only when enabled and only through the approved service path |
| Cash movement approval | `Cash::Commands::TransferCash`, `Cash::Commands::ApproveCashMovement` | `cash.movement.create`, `cash.movement.approve`; no-self-approval | Vault-involved or policy-controlled custody movements require approval; ordinary internal movement remains no-GL |
| Cash count and variance approval | `Cash::Commands::RecordCashCount`, `Cash::Commands::ApproveCashVariance` | `cash.count.record`, `cash.variance.approve`; no-self-approval | Count creates evidence; approved variance posts `cash.variance.posted` through `Core::Posting` |
| Business-date close | `Core::BusinessDate::Commands::CloseBusinessDate`, `Teller::Queries::EodReadiness` | `business_date.close`; readiness checks | Business date advances only when readiness passes; close is audit-recorded |
| Operational event posting | `Core::Posting::Commands::PostEvent` | event state, posting rules, open posting date | Pending financial events post only through the posting command; controllers do not build journals |

Recommended UI treatment:

- Show the missing capability or failed invariant in plain language.
- Prefer blocking errors for invariant failures and missing required approval.
- Use warnings only for conditions that can still legitimately proceed, such as record-only mode or stale preview risk.
- Do not encode no-self-approval or posting eligibility only in views; those checks belong in domain commands.
- Do not introduce a generic supervisor credential prompt as the source of approval truth. If added later, it should resolve to the same capability-checked command inputs.

## Search and Retrieval

The teller surface should provide minimal retrieval over existing read models:

- session-scoped recent transactions
- today's teller activity
- account activity lookup
- operational event detail
- receipt or trace reprint where supported
- filters by account, event type, reference id, idempotency key, and session where available

Ops-oriented investigation, broad event search, close packages, and exception review remain better suited to the Ops workspace.

## MVP Test Plan

The teller MVP should be proven by a focused set of integration and domain tests. The goal is not to test every screen variation, but to prove that each control boundary and financial invariant survives the teller workflow.

| Test area | Primary evidence | What must be proven |
| --- | --- | --- |
| Branch transaction forms | `test/integration/branch_transaction_forms_test.rb` | Deposits, withdrawals, and transfers can record-only or record-and-post; forms preserve idempotency; teller-session policy errors are visible |
| Teller JSON money flows | `test/integration/teller/teller_requests_test.rb`, operational-event integration tests | Existing JSON `/teller` behavior remains stable while Branch HTML flows wrap the same domain commands |
| Session cash policy | `test/integration/teller/teller_session_cash_policy_test.rb`, `test/domains/teller/expected_cash_for_session_test.rb` | Expected cash uses opening snapshot plus **posted** teller cash events (pending excluded); deposits increase expected cash and withdrawals decrease it when posted; session-attributed movements participate when configured; missing/closed sessions are rejected where configured |
| NSF and available balance | `test/integration/teller/overdraft_nsf_test.rb`, `test/domains/accounts/authorize_debit_test.rb` | Insufficient funds create `overdraft.nsf_denied` evidence and forced fee behavior rather than invalid postings |
| Check and combined deposits | `test/domains/core/operational_events/accept_check_deposit_test.rb`, `test/domains/core/operational_events/accept_deposit_ticket_test.rb`, `test/integration/teller/check_deposit_accepted_test.rb`, `test/integration/branch_check_deposit_test.rb`, `test/integration/branch_deposit_ticket_test.rb` | Multi-item check deposits post through `AcceptCheckDeposit`; combined tickets preserve cash/check child event semantics, support optional check-only event-level holds, and do not project checks into teller cash |
| Holds | `test/integration/teller/holds_deposit_linked_test.rb`, `test/domains/accounts/place_hold_deposit_link_test.rb`, `test/domains/accounts/expire_due_holds_test.rb` | Holds are no-GL, affect available balance, enforce deposit-link rules, and can release/expire through controlled paths |
| Reversals | `test/domains/core/operational_events/record_reversal_deposit_hold_guard_test.rb`, reversal integration coverage | Reversals create linked compensating events and journals; guarded events are rejected |
| Fee waiver and servicing controls | `test/integration/branch_customer_servicing_test.rb`, capability tests | Supervisor/capability-gated fee waiver and hold release remain controlled and traceable |
| Teller variance | `test/integration/teller/teller_session_variance_test.rb`, `test/domains/core/operational_events/record_event_drawer_variance_test.rb` | Variance threshold routes to supervisor approval; optional GL drawer variance posts only when enabled |
| Cash custody | `test/domains/cash/cash_inventory_test.rb`, `test/integration/teller/cash_inventory_json_test.rb`, Branch cash form coverage | Cash movements update custody balances, enforce approval/no-self-approval, and do not create GL for ordinary internal transfers |
| Trial balance and EOD readiness | `test/integration/teller/reports_trial_balance_and_eod_test.rb`, `test/integration/ops_eod_and_events_test.rb` | Trial balance and readiness expose pending/open work without mutating financial truth |
| Authorization surfaces | `test/integration/branch_authorized_surfaces_test.rb`, `test/domains/workspace/capability_resolver_test.rb` | Teller, supervisor, operations, CSR, and admin capabilities gate the intended surfaces |

Minimum end-to-end MVP proof:

1. Open a teller session.
2. Record and post a cash deposit.
3. Record and post a cash withdrawal.
4. Exercise an NSF denial path.
5. Complete an account transfer.
6. Place and release a hold.
7. Record and post a combined cash/check deposit ticket, with optional check event-level hold evidence.
8. Reverse an eligible posted event.
9. Close the teller session with server-computed expected vs operator-supplied actual count.
10. Move cash between vault and drawer and prove ordinary custody movement is no-GL.
11. Confirm trial balance/EOD readiness reflects unresolved teller work.

Tests should prefer existing domain commands and workspace routes over new generic transaction abstractions. If implementation later adds preview endpoints, tests should assert that previews are advisory and that command execution re-checks state before commit.

## Post-MVP / Requires ADR

The following capabilities are legitimate banking needs, but they veer beyond BankCORE's current teller MVP. They should not be folded into Teller without explicit ownership, event, posting, and control decisions.

| Capability | Likely owner | Why it is not teller MVP |
| --- | --- | --- |
| Check clearing, returns, and settlement | `Integration`, `Accounts`, possibly future item-processing domain | Accepted check deposits are shipped, but clearing lifecycle, returns, collection risk, and settlement-specific item state remain outside the narrow intake slice |
| Check cashing | future `Instruments` or check domain, `Cash`, `Core::Posting` | Requires presenter authority, check item lifecycle, limits, returns, and cash payout risk |
| Official check / bank draft issuance | future `Instruments` | Requires instrument records, liability account, issue/void/paid/replacement lifecycle, reconciliation |
| Loan payment | `Loans`, `Core::Posting` | Requires loan servicing, amortization, allocation, delinquency, and loan GL rules |
| GL miscellaneous receipt | `Core::Ledger` plus a controlled Operations/Admin surface | Non-account GL intake is high-risk and should not be a generic teller shortcut |
| Item-level check holds, release, and reversal | item-processing domain plus `Integration` / `Accounts` | Multi-item accepted deposits are shipped with event-level holds only; item-specific availability, release, return, and reversal semantics require separate ownership and controls |
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

BankCORE should treat Teller as a controlled transaction entry surface, not a catch-all banking operations module. The MVP teller surface covers cash deposits, accepted check deposits, combined cash/check deposit tickets, cash withdrawals, account transfers, manual fees and waivers, holds, controlled reversals, teller sessions, drawer variance, receipt/trace evidence, and initiation of internal cash custody movements. The system guarantee is that financial impact flows through operational events and balanced posting, while physical cash custody flows through Cash locations and movements.

Check clearing/returns, check cashing, official checks, loan payments, miscellaneous GL receipts, generalized approval queues, denomination-level activity, and document-grade receipts are valid future capabilities, but they belong to later domain-owned slices with explicit ADR coverage.
