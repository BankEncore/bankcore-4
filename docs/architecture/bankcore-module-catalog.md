# BankCORE Module Catalog

**Status:** Draft
**Classification:** DROP-IN SAFE
**Suggested path:** `docs/architecture/module-catalog.md`

---

## 1. Purpose

This document defines the recommended modular architecture for BankCORE as a **single Rails application with strict internal domain boundaries**, plus a limited set of optional edge engines for externally facing or highly separable features.

The goal is to:

* preserve financial correctness and transactional integrity
* prevent uncontrolled coupling across banking domains
* keep the accounting kernel tightly governed
* support later extraction of selected modules where justified
* provide a stable structure for code organization, naming, ownership, and dependency control

This document is intentionally implementation-oriented.

---

## 2. Architectural stance

BankCORE should begin as a **modular monolith**.

The financial center of the application should remain inside the primary Rails app, organized by domain namespaces rather than by controllers, generic service objects, or premature microservices.

### 2.1 Core principles

1. **One transactional core** for posting, ledger, and business-date governance.
2. **Strict domain boundaries** inside the application.
3. **Workspace-oriented controllers** that orchestrate domain services rather than owning business logic.
4. **Explicit table ownership** by module.
5. **Domain events and command/query boundaries** between modules.
6. **Optional engines only at the edge**, not for the accounting kernel.

---

## 3. Domain map

### 3.1 Financial kernel

These domains form the accounting and operational center of the system.

* `Core::OperationalEvents`
* `Core::Posting`
* `Core::Ledger`
* `Core::BusinessDate`

### 3.2 Customer and contract domains

These domains define customers, products, and account contracts.

* `Party`
* `Products`
* `Accounts`

### 3.3 Servicing domains

These domains apply product behavior and account servicing rules.

* `Deposits`
* `Loans`
* `Limits`

### 3.4 Operational domains

These domains support branch/workstation operations.

* `Teller`
* `Cash`
* `Workflow`

### 3.5 Control and support domains

These domains provide oversight, evidence, read models, and external connectivity.

* `Compliance`
* `Documents`
* `Reporting`
* `Integration`

---

## 4. Repo structure

```text
bankcore/
├─ app/
│  ├─ controllers/
│  │  ├─ admin/
│  │  ├─ api/
│  │  ├─ customer_service/
│  │  ├─ ops/
│  │  └─ teller/
│  ├─ domains/
│  │  ├─ core/
│  │  │  ├─ operational_events/
│  │  │  ├─ posting/
│  │  │  ├─ ledger/
│  │  │  └─ business_date/
│  │  ├─ party/
│  │  ├─ products/
│  │  ├─ accounts/
│  │  ├─ deposits/
│  │  ├─ loans/
│  │  ├─ limits/
│  │  ├─ teller/
│  │  ├─ cash/
│  │  ├─ workflow/
│  │  ├─ compliance/
│  │  ├─ documents/
│  │  ├─ reporting/
│  │  └─ integration/
│  ├─ jobs/
│  ├─ models/
│  ├─ policies/
│  ├─ presenters/
│  ├─ queries/
│  ├─ services/
│  └─ views/
├─ config/
│  ├─ initializers/
│  ├─ routes/
│  │  ├─ admin.rb
│  │  ├─ api.rb
│  │  ├─ customer_service.rb
│  │  ├─ ops.rb
│  │  └─ teller.rb
│  └─ routes.rb
├─ db/
│  ├─ migrate/
│  ├─ seeds/
│  │  ├─ gl/
│  │  ├─ products/
│  │  └─ system/
│  └─ schema.rb
├─ docs/
│  ├─ adr/
│  ├─ architecture/
│  ├─ controls/
│  ├─ domains/
│  ├─ events/
│  └─ runbooks/
├─ lib/
│  ├─ bankcore/
│  │  ├─ errors/
│  │  ├─ instrumentation/
│  │  ├─ money/
│  │  └─ support/
│  └─ tasks/
├─ spec/
│  ├─ domains/
│  ├─ integration/
│  ├─ requests/
│  ├─ support/
│  └─ system/
└─ engines/
   ├─ admin_console/
   ├─ api_gateway/
   ├─ customer_portal/
   └─ reporting_portal/
```

---

## 5. Domain-internal structure

Each domain should use a repeatable internal structure.

```text
app/domains/accounts/
├─ commands/
├─ events/
├─ models/
├─ policies/
├─ queries/
├─ services/
├─ validators/
└─ value_objects/
```

### 5.1 Subfolder meanings

#### `models/`

Persistence-backed records owned by the domain.

#### `commands/`

State-changing application actions.

Examples:

* open account
* close teller session
* place hold
* assess fee
* reverse event

#### `queries/`

Read-side retrieval and search objects.

Examples:

* account search
* event search
* teller balancing summary
* approval queue

#### `services/`

Domain logic that does not fit on a single model.

#### `events/`

Internal domain event classes or event-name constants.

#### `policies/`

Domain business rules and eligibility logic.

#### `validators/`

Complex validations beyond model-level presence/format checks.

#### `value_objects/`

Structured non-persistent types.

Examples:

* money amount
* approval window
* balance snapshot
* account profile

---

## 6. Module catalog

### 6.1 `Core::OperationalEvents`

**Purpose:** canonical business-event recording layer.

**Owns:**

* event records
* reversal linkage
* idempotency references
* actor/channel/session metadata
* business-date attribution

**Typical contents:**

* `EventRecord`
* `ReversalLink`
* `RecordEvent`
* `ReverseEvent`
* `EventSearch`
* `EventCatalog`
* `EventClassifier`

**Shipped (narrow observability read — [ADR-0017](../adr/0017-deposit-products-fk-narrow-scope.md) §2.5):**

* `Core::OperationalEvents::Queries::ListOperationalEvents` — bounded listing by `business_date` with product-aware account context and posting/journal id traceability (read-only).

**Shipped (code-first event catalog — [ADR-0019](../adr/0019-event-catalog-and-fee-events.md)):**

* `Core::OperationalEvents::EventCatalog` — metadata for known `event_type` strings (not a second DB truth); CI drift checks align catalog **financial** rows with `PostingRules::Registry::HANDLERS`.
* Teller **`GET /teller/event_types`** — discovery JSON for clients (same operator header as other teller reads).

**Rules:**

* all material banking actions should become durable operational events
* reversal should be modeled explicitly, not by silent mutation

---

### 6.2 `Core::Posting`

**Purpose:** convert business events into balanced accounting instructions and committed posting batches.

**Owns:**

* posting batches
* posting legs
* posting rule resolution
* balancing validation
* posting commit orchestration

**Typical contents:**

* `PostingBatch`
* `PostingLeg`
* `PostEvent`
* `PreviewPosting`
* `ReversePosting`
* `PostingRuleResolver`
* `PostingBuilder`
* `BalancingValidator`

**Rules:**

* posting logic must not live in controllers
* posting must remain deterministic and balanced

---

### 6.3 `Core::Ledger`

**Purpose:** institutional books and journal persistence.

**Owns:**

* GL accounts
* journal entries
* journal lines
* financial periods
* trial balance queries/services

**Typical contents:**

* `GlAccount`
* `JournalEntry`
* `JournalLine`
* `FinancialPeriod`
* `TrialBalanceQuery`
* `TrialBalanceService`
* `ClosePeriod`

**Rules:**

* no channel module writes journal lines directly
* ledger truth is append-oriented and tightly controlled

---

### 6.4 `Core::BusinessDate`

**Purpose:** operational date governance and day-close orchestration.

**Owns:**

* business-day state
* day checkpoints
* open/close/reopen/advance actions
* close validations
* EOD orchestration

**Shipped (narrow Phase 2 slice — [ADR-0018](../adr/0018-business-date-close-and-posting-invariant.md)):**

* `Core::BusinessDate::Models::BusinessDateSetting` / `BusinessDateCloseEvent`
* `Core::BusinessDate::Services::CurrentBusinessDate`, `AssertOpenPostingDate`
* `Core::BusinessDate::Commands::SetBusinessDate`, `CloseBusinessDate` (EOD-gated advance + audit); `AdvanceBusinessDate` **test-only**
* `Teller::Queries::EodReadiness` (readiness composition; [ADR-0016](../adr/0016-trial-balance-and-eod-readiness.md))

**Still aspirational / later ADRs:**

* `BusinessDayCheckpoint`, multi-entity dates, `EndOfDayOrchestrator`, day **reopen**

---

### 6.5 `Party`

**Purpose:** customer/party system of record.

**Owns:**

* party records
* party relationships
* addresses
* phone numbers
* email addresses
* identity references

**Typical contents:**

* `PartyRecord`
* `PartyRelationship`
* `PartyAddress`
* `PartyPhone`
* `PartyEmail`
* `IdentityDocument`
* `CreateParty`
* `MergeParties`
* `PartySearch`
* `Party360Query`

---

### 6.6 `Products`

**Purpose:** product configuration and behavior templates.

**Owns:**

* deposit products
* loan products
* fee schedules
* interest rules
* posting templates
* limit templates

**Typical contents:**

* `DepositProduct`
* `LoanProduct`
* `FeeSchedule`
* `InterestRule`
* `PostingTemplate`
* `ProductResolver`
* `FeeRuleResolver`
* `InterestRuleResolver`
* `GlMappingResolver`

---

### 6.7 `Accounts`

**Purpose:** account contract and state model.

**Owns:**

* deposit accounts
* loan accounts
* account relationships
* account restrictions
* account notes
* lifecycle state

**Typical contents:**

* `DepositAccount`
* `LoanAccount`
* `AccountRelationship`
* `AccountRestriction`
* `OpenAccount`
* `CloseAccount`
* `FreezeAccount`
* `AccountSearch`
* `OwnershipResolver`

**Rules:**

* accounts own contractual/account state
* accounts do not replace posting or journal truth

---

### 6.8 `Deposits`

**Purpose:** deposit servicing behavior.

**Owns:**

* interest accrual orchestration
* interest posting orchestration
* fee assessment and waiver orchestration
* overdraft decisioning
* statement-cycle logic
* maturity processing for supported deposit types

**Typical contents:**

* `AccrueInterest`
* `PostInterest`
* `AssessFee`
* `WaiveFee`
* `ProcessReturnedDepositItem`
* `InterestAccrualService`
* `FeeAssessmentService`
* `OverdraftDecisionService`
* `StatementCycleService`

---

### 6.9 `Loans`

**Purpose:** loan servicing behavior.

**Owns:**

* amortization schedules
* payment application logic
* accrual logic
* delinquency state transitions
* charge-off and recovery orchestration

**Typical contents:**

* `AmortizationSchedule`
* `LoanPaymentAllocation`
* `DelinquencyState`
* `ApplyPayment`
* `AccrueInterest`
* `ChargeOffLoan`
* `PaymentAllocator`
* `ChargeOffService`

---

### 6.10 `Limits`

**Purpose:** available-funds and authorization controls.

**Owns:**

* monetary holds
* transaction limits
* authorization decision logs
* hold expiration/release logic

**Typical contents:**

* `MonetaryHold`
* `TransactionLimit`
* `AuthorizationDecisionLog`
* `PlaceHold`
* `ReleaseHold`
* `AuthorizeTransaction`
* `AvailableBalanceCalculator`
* `LimitEvaluator`

---

### 6.11 `Teller`

**Purpose:** workstation-facing transactional flows.

**MVP implementation:** drawer lifecycle, expected vs actual cash, variance, and supervisor approval live on **`teller_sessions`** with HTTP under `app/controllers/teller/*` ([ADR-0014](../adr/0014-teller-sessions-and-control-events.md), [ADR-0015](../adr/0015-teller-workspace-authentication.md)). Financial effect still flows through **`Core::OperationalEvents`** + **`Core::Posting`**; read-only **trial balance / EOD readiness** composition lives in `Teller::Queries::EodReadiness` ([ADR-0016](../adr/0016-trial-balance-and-eod-readiness.md)).

**Owns:**

* teller sessions
* teller transactions
* override requests
* receipt records and builders
* balancing summaries

**Typical contents:**

* `TellerSession`
* `TellerTransaction`
* `TellerOverrideRequest`
* `ReceiptRecord`
* `OpenSession`
* `CloseSession`
* `PerformCashDeposit`
* `PerformWithdrawal`
* `RecentActivityQuery`
* `SessionBalancer`

---

### 6.12 `Cash`

**Purpose:** cash location and cash-movement control.

**Owns:**

* cash locations
* vault transfers
* cash counts
* cash adjustments
* cash reconciliation artifacts

**Typical contents:**

* `CashLocation`
* `VaultTransfer`
* `CashCount`
* `CashAdjustment`
* `TransferCash`
* `RecordCashCount`
* `ReconcileCashLocation`
* `CashPositionQuery`

---

### 6.13 `Workflow`

**Purpose:** approvals and maker-checker controls.

**Owns:**

* approval requests
* approval decisions
* approval policies
* approval windows and expiration logic

**Typical contents:**

* `ApprovalRequest`
* `ApprovalDecision`
* `ApprovalPolicy`
* `SubmitForApproval`
* `ApproveRequest`
* `DeclineRequest`
* `ApprovalQueueQuery`
* `ApprovalPolicyEvaluator`

---

### 6.14 `Compliance`

**Purpose:** compliance evidence and case-link support.

**Owns:**

* CTR case records
* sanctions-screening results or references
* AML alert references
* evidence links

**Typical contents:**

* `CtrCase`
* `SanctionsScreeningResult`
* `AmlAlertReference`
* `ComplianceEvidenceRecord`
* `CtrAggregator`
* `SanctionsAdapter`

---

### 6.15 `Documents`

**Purpose:** document metadata and retention-oriented document handling.

**Owns:**

* document records
* document links
* retention flags/policies
* storage adapter contracts

**Typical contents:**

* `DocumentRecord`
* `DocumentLink`
* `RetentionPolicy`
* `AttachDocument`
* `ArchiveDocument`
* `StorageAdapter`

---

### 6.16 `Reporting`

**Purpose:** read-optimized projections and extracts.

**Owns:**

* daily balance snapshots
* reporting extracts
* read projections
* reporting refresh/materialization services

**Typical contents:**

* `DailyBalanceSnapshot`
* `ReportingExtract`
* `DailyTrialBalanceQuery`
* `TellerActivityReportQuery`
* `ProjectionRefresher`
* `SnapshotMaterializer`

**Rules:**

* reporting is read-side only
* reporting must not serve as the operational write model

---

### 6.17 `Integration`

**Purpose:** inbound/outbound adapter layer.

**Owns:**

* ingestion commands for rails/files
* outbound event publishing
* idempotent inbound processing helpers
* canonical adapter contracts

**Typical contents:**

* `IngestAchFile`
* `IngestWireFile`
* `PublishDomainEvent`
* `AchAdapter`
* `WireAdapter`
* `CardSettlementAdapter`
* `OutboundEventPublisher`
* `IdempotencyGateway`

---

## 7. Controller and workspace conventions

Controllers should be organized by **workspace**, not by deep internal domain ownership.

### 7.1 Workspaces

* `Teller`
* `CustomerService`
* `Ops`
* `Admin`
* `Api`

### 7.2 Example controllers

* `Teller::TransactionsController`
* `Teller::SessionsController`
* `CustomerService::PartiesController`
* `CustomerService::DepositAccountsController`
* `Ops::OperationalEventsController`
* `Ops::BusinessDatesController`
* `Admin::DepositProductsController`

### 7.3 Controller rule

Controllers should:

* validate and normalize input
* call commands/queries/orchestrators
* prepare response/view state

Controllers should not:

* construct journal lines
* contain posting rules
* implement account-balance math
* make direct cross-domain mutations without going through the proper commands/services

---

## 8. Naming conventions

### 8.1 Modules

Prefer short banking-domain names.

Good:

* `Party`
* `Accounts`
* `Deposits`
* `Workflow`
* `Core::Posting`

Avoid:

* oversized descriptive namespaces
* vague global namespaces like `Services` or `Helpers` as architectural anchors

### 8.2 Commands

Use imperative verb phrases.

Examples:

* `Accounts::Commands::OpenAccount`
* `Teller::Commands::CloseSession`
* `Deposits::Commands::AssessFee`
* `Core::Posting::Commands::PostEvent`

### 8.3 Queries

Use noun + intent.

Examples:

* `Accounts::Queries::AccountSearch`
* `Teller::Queries::SessionSummary`
* `Reporting::Queries::DailyTrialBalance`
* `Core::OperationalEvents::Queries::EventSearch`

### 8.4 Services

Prefer role-based names.

Good:

* `OwnershipResolver`
* `PostingRuleResolver`
* `ApprovalPolicyEvaluator`
* `BalanceProjector`

Avoid:

* `Manager`
* `Helper`
* `UtilService`

### 8.5 Business event names

Use business semantics, not technical row semantics.

Good:

* `deposit.accepted`
* `withdrawal.posted`
* `fee.assessed`
* `interest.accrued`
* `teller_session.closed`

Avoid:

* `row.updated`
* `record.saved`

---

## 9. Dependency rules

### 9.1 Allowed direction

* controllers → commands / queries / orchestrators
* commands → domain services and owned models
* domain services → other domains only through explicit contracts
* reporting/read models → subscribe to events or query published state

### 9.2 Forbidden direction

* controllers creating journal entries or journal lines directly
* teller code writing directly to GL structures
* reporting code mutating operational records
* integrations directly mutating account balances
* deposits or loans bypassing operational events and posting when a financial effect is created

---

## 10. Database ownership rules

Each table family should have **one owning domain** even if all tables live in one schema.

| Table family                                                 | Owning module             |
| ------------------------------------------------------------ | ------------------------- |
| `party_*`                                                    | `Party`                   |
| `deposit_products`, `product_*`, `fee_*`, `interest_*`      | `Products`                |
| `deposit_accounts`, `loan_accounts`, `deposit_account_parties`, `loan_account_parties`, `account_relationships` | `Accounts`                |
| `operational_events`, `reversal_links`                       | `Core::OperationalEvents` |
| `posting_batches`, `posting_legs`                            | `Core::Posting`           |
| `journal_entries`, `journal_lines`, `gl_accounts`            | `Core::Ledger`            |
| `holds`                                                      | `Accounts`                |
| `authorization_decisions`                                    | `Limits`                  |
| `operators`                                                  | `Workspace`               |
| `teller_sessions`, `teller_transactions`                     | `Teller`                  |
| `cash_locations`, `vault_transfers`, `cash_counts`           | `Cash`                    |
| `approval_requests`, `approval_decisions`                    | `Workflow`                |
| `document_records`                                           | `Documents`               |
| `daily_balance_snapshots`, `reporting_extracts`              | `Reporting`               |

---

## 11. Routes structure

Routes should be split by workspace.

### `config/routes.rb`

```ruby
Rails.application.routes.draw do
  draw :teller
  draw :customer_service
  draw :ops
  draw :admin
  draw :api
end
```

### `config/routes/teller.rb`

```ruby
namespace :teller do
  resource :session, only: %i[show create destroy]
  resources :transactions, only: %i[new create index show]
  resources :receipts, only: %i[show]
  resources :cash_transfers, only: %i[new create index show]
end
```

### `config/routes/customer_service.rb`

```ruby
namespace :customer_service do
  resources :parties
  resources :deposit_accounts
  resources :loan_accounts
  resources :documents, only: %i[index show create]
end
```

### `config/routes/ops.rb`

```ruby
namespace :ops do
  resources :operational_events, only: %i[index show]
  resources :journal_entries, only: %i[index show]
  resources :business_dates, only: %i[index show] do
    post :close_day, on: :collection
    post :advance_day, on: :collection
  end
end
```

---

## 12. Testing layout

Tests should follow the same boundaries as the application.

```text
spec/
├─ domains/
│  ├─ core/
│  │  ├─ operational_events/
│  │  ├─ posting/
│  │  ├─ ledger/
│  │  └─ business_date/
│  ├─ party/
│  ├─ products/
│  ├─ accounts/
│  ├─ deposits/
│  ├─ loans/
│  ├─ limits/
│  ├─ teller/
│  ├─ cash/
│  ├─ workflow/
│  ├─ compliance/
│  ├─ documents/
│  ├─ reporting/
│  └─ integration/
├─ requests/
├─ system/
└─ integration/
```

### 12.1 Test categories

* **domain specs**: banking behavior inside one domain
* **integration specs**: end-to-end cross-domain financial flows
* **request specs**: controller and API contract behavior
* **system specs**: operator-facing workflows

---

## 13. Starter class list

The following initial classes provide a practical starting point.

### Financial kernel

* `Core::OperationalEvents::Models::EventRecord`
* `Core::OperationalEvents::Commands::RecordEvent`
* `Core::Posting::Commands::PostEvent`
* `Core::Posting::Services::PostingBuilder`
* `Core::Posting::Services::BalancingValidator`
* `Core::Ledger::Models::JournalEntry`
* `Core::Ledger::Models::JournalLine`
* `Core::BusinessDate::Services::CurrentBusinessDate`

### Customer and contract foundation

* `Party::Models::PartyRecord`
* `Party::Queries::PartySearch`
* `Products::Models::DepositProduct`
* `Products::Services::GlMappingResolver`
* `Accounts::Models::DepositAccount`
* `Accounts::Models::AccountRelationship`
* `Accounts::Commands::OpenAccount`

### Control and operations foundation

* `Limits::Services::AvailableBalanceCalculator`
* `Limits::Commands::PlaceHold`
* `Teller::Models::TellerSession`
* `Teller::Commands::OpenSession`
* `Teller::Commands::PerformCashDeposit`
* `Workflow::Models::ApprovalRequest`
* `Workflow::Commands::SubmitForApproval`

---

## 14. Engines roadmap

Engines should be reserved for separable edge features.

### 14.1 Good engine candidates

* `engines/api_gateway/`
* `engines/customer_portal/`
* `engines/reporting_portal/`
* `engines/admin_console/`

### 14.2 Do not extract early

The following should remain inside the main app unless there is a very strong reason otherwise:

* `Core::OperationalEvents`
* `Core::Posting`
* `Core::Ledger`
* `Core::BusinessDate`
* `Accounts`

---

## 15. Implementation notes

1. Start with **one application and one database**.
2. Enforce domain boundaries through directory structure, naming, commands/queries, and table ownership.
3. Keep the financial kernel centralized.
4. Use events/contracts internally even before introducing external messaging.
5. Extract only edge-facing concerns after boundaries stabilize.

---

## 16. Non-goals

This document does not define:

* full data-field specifications for every table
* event-type registry contents
* posting templates or GL mapping details
* UI design contracts
* authorization policy matrices

Those should be documented in separate ADRs and domain-specific technical specs.

---

## 17. Summary

BankCORE should be structured as a **modular monolith with a tightly governed financial kernel**.

The main Rails app should contain the core banking domains under `app/domains/`, while controllers remain workspace-oriented and engines are reserved for externally facing or highly separable edge features.

This structure provides:

* strong financial control
* practical Rails implementation boundaries
* cleaner ownership rules
* improved testability
* a credible path to later extraction without fragmenting the accounting center too early
