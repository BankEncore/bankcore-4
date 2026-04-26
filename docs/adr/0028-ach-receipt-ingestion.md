# ADR-0028: ACH receipt ingestion

**Status:** Accepted  
**Date:** 2026-04-25  
**Aligns with:** [ADR-0002](0002-operational-event-model.md), [ADR-0012](0012-posting-rule-registry-and-journal-subledger.md), [ADR-0019](0019-event-catalog-and-fee-events.md), [ADR-0027](0027-external-read-api-boundary.md), [roadmap](../roadmap.md) Phase 4.7

---

## 1. Context

Phase 4.7 is the first external money-moving channel. The safest first slice is inbound ACH receipt for a narrow deposit-credit path: parse a minimal structured file representation, resolve an account by account number, record a durable operational event, post through the registry, and leave support/reconciliation evidence.

This ADR intentionally starts smaller than a full ACH product. It proves the integration-to-posting path without ACH origination, debits, full NACHA parsing, returns, effective-entry-date warehousing, or customer/partner submission APIs.

Decision drivers:

- every financial effect must flow through `operational_events` and `Core::Posting`
- file/item retries must not create duplicate customer credits
- support must find an ACH item from stable external identifiers
- EOD readiness must remain explainable when ACH ingestion creates pending work
- the first slice should not require broad account-party expansion or receiver-name matching

---

## 2. Decision

Phase 4.7 will add a first-slice inbound ACH credit path centered on one customer-posting event type:

- `ach.credit.received`

The event represents one accepted inbound ACH credit item that is posted to one open deposit account.

### 2.1 Event taxonomy

`ach.credit.received` is the only ACH operational event type in the first implementation.

Catalog expectations:

| Field | Value |
| --- | --- |
| Category | `financial` |
| GL posting | Yes |
| Lifecycle | `pending_to_posted` |
| Record command | ACH receipt ingestion command or equivalent dedicated command |
| Allowed channel | `batch` |
| Customer visible | Yes |
| Statement visible | Yes |
| Support search keys | `source_account_id`, `reference_id`, `idempotency_key` |

Deferred ACH event types include `ach.file.received`, `ach.batch.accepted`, `ach.item.rejected`, `ach.return.received`, and `ach.credit.returned`. Add them only when a later ACH depth slice needs durable lifecycle state beyond the posted customer credit event.

### 2.2 Channel

First-slice ACH receipt ingestion uses existing channel `batch`.

Rationale: `batch` already represents supervised file or engine activity and is present in the operational-event channel allowlist. A dedicated `ach` channel can be added later if support/reporting need rail identity at the channel level instead of through `event_type`, reference conventions, and future file/item metadata.

### 2.3 Idempotency

ACH receipt idempotency is deterministic at the item level.

The first implementation must build:

```text
idempotency_key = ach-credit-received:{file_id}:{batch_id}:{item_id}
```

`file_id`, `batch_id`, and `item_id` are normalized strings supplied by the ingestion command's structured input for the first slice.

Rules:

- Same file/batch/item replay must return the same item outcome and must not double-post.
- Same key with different account number, amount, currency, business date, or item metadata must fail as an idempotency mismatch.
- File-level and batch-level idempotency are documented by the composed item key but are not separate persisted lifecycle events in this slice.
- If a later implementation adds ACH file/batch/item tables, those tables must preserve the same item-level duplicate protection.

### 2.4 Account lookup

ACH item account lookup uses exact `deposit_accounts.account_number`.

Rules:

- The account number must identify one `Accounts::Models::DepositAccount`.
- The account must be `open`.
- Currency must be `USD`.
- The lookup must be owned by `Accounts`, for example `Accounts::Queries::FindDepositAccountByAccountNumber`.
- Integration/ACH code must not embed account lookup rules directly.

Party and receiver-name matching are out of scope for the first slice. Ops/support views may display current account parties for review, but party/name mismatch must not block first-slice posting until a later ADR defines receiver-name validation.

### 2.5 Settlement GL

ACH settlement must use a dedicated settlement or suspense GL account, not teller cash.

Decision:

- Add a new active USD asset GL account for ACH settlement, for example **1120 ACH Settlement**.
- Do not reuse **1110 Cash in Vaults**; teller cash/vault controls are not ACH network settlement controls.

Posting for `ach.credit.received`:

| Leg | GL | Side | Subledger |
| --- | --- | --- | --- |
| 1 | ACH settlement asset (for example `1120`) | debit | none |
| 2 | `2110` customer DDA liability | credit | `source_account_id` |

The event amount is stored in minor units and currency must be USD for this slice.

### 2.6 Business date and cutoff

First-slice ACH receipt posts only on the current open business date.

Rules:

- ACH ingestion must use existing open-posting-date validation.
- It must not post into a closed day or future day.
- Effective-entry-date handling, cutoff queues, settlement-date warehousing, and next-day posting are deferred.
- Prefer record-and-post-immediately for accepted first-slice credits. This proves the complete money movement path and keeps EOD behavior simple.
- If an accepted ACH event remains `pending`, existing EOD readiness rules treat it as pending operational work and block close until posted or otherwise resolved.

### 2.7 Support search

Support must be able to find the ACH item through Phase 4.5 operational-event search fields.

First-slice convention:

```text
reference_id = ach:{file_id}:{batch_id}:{item_id}
idempotency_key = ach-credit-received:{file_id}:{batch_id}:{item_id}
```

The catalog entry for `ach.credit.received` must declare:

```text
support_search_keys = source_account_id, reference_id, idempotency_key
```

Dedicated ACH file/item columns are deferred unless the first implementation chooses persistent file/item tables for reconciliation. If such tables are added, support search must still be able to navigate from file/item identifiers to the operational event.

### 2.8 Reconciliation evidence

Every accepted and posted ACH credit item must be traceable from inbound item through ledger impact.

Required evidence per item:

- file id
- batch id
- item id or trace id
- inbound account number
- resolved deposit account id
- operational event id
- event `reference_id`
- event `idempotency_key`
- posting batch id
- journal entry id
- ACH settlement GL line
- customer DDA `2110` line with `deposit_account_id`

The first implementation may return this evidence from the ingestion command and prove it through integration tests. A persistent ACH file/batch/item model is optional in the first slice; add it only if command-returned evidence is insufficient for support workflows.

---

## 3. Worked Example

Input item:

```json
{
  "file_id": "file-20260425-001",
  "batch_id": "batch-1",
  "item_id": "trace-091000019-000001",
  "account_number": "DAABC123",
  "amount_minor_units": 12500,
  "currency": "USD"
}
```

Operational event:

```json
{
  "event_type": "ach.credit.received",
  "channel": "batch",
  "idempotency_key": "ach-credit-received:file-20260425-001:batch-1:trace-091000019-000001",
  "reference_id": "ach:file-20260425-001:batch-1:trace-091000019-000001",
  "source_account_id": 42,
  "amount_minor_units": 12500,
  "currency": "USD"
}
```

Posting sketch:

| Seq | GL | Side | Amount | Deposit account |
| --- | --- | --- | ---: | --- |
| 1 | `1120` ACH Settlement | debit | 12,500 | none |
| 2 | `2110` DDA liability | credit | 12,500 | 42 |

---

## 4. Explicit Deferrals

This ADR does **not** add:

- ACH origination
- ACH debits
- returns or representment workflows
- full NACHA parser and validation matrix
- effective-entry-date warehousing
- cutoff queues
- prenotes
- NOCs
- ACH reversals
- disputes or provisional credit
- OFAC, AML, sanctions, or fraud workflows
- customer/partner API submission
- broad account-party expansion
- receiver-name fuzzy matching
- multi-bank routing/transit support beyond placeholders in structured input

---

## 5. Implementation Checklist

After this ADR is accepted, the implementation should update:

- `Core::OperationalEvents::EventCatalog`
- `Core::OperationalEvents::Commands::RecordEvent` allowlist/fingerprint or a dedicated ACH command with equivalent idempotency checks
- `Core::Posting::PostingRules::Registry`
- a new ACH posting rule under `app/domains/core/posting/posting_rules/`
- seeded COA for ACH settlement GL
- `Accounts::Queries::FindDepositAccountByAccountNumber`
- an ACH receipt ingestion command under the ADR-approved Integration/ACH namespace
- `docs/operational_events/README.md`
- `docs/operational_events/ach-credit-received.md`
- focused tests proving account lookup, idempotency, posting, support search, reconciliation, and EOD behavior

---

## 6. Consequences

Positive:

- Proves the first external money-moving channel through existing operational-event and posting invariants.
- Keeps ACH receipt narrow enough to test in one end-to-end integration path.
- Preserves support search through existing Phase 4.5 filters.

Negative:

- Full ACH lifecycle state is deferred; support cannot yet manage returns or rejected item workflows in the application.
- Structured input delays full NACHA parser validation.
- Settlement GL must be added before posting can ship.

Neutral:

- Account-party expansion is not required for the first receipt slice.
- Existing `/teller`, Branch, Ops, Admin, and external read API boundaries remain unchanged.

---

## 7. Related ADRs

- [ADR-0002](0002-operational-event-model.md) — operational events, idempotency, and integration role.
- [ADR-0012](0012-posting-rule-registry-and-journal-subledger.md) — posting registry and DDA subledger rules.
- [ADR-0019](0019-event-catalog-and-fee-events.md) — code-first event catalog and drift checks.
- [ADR-0027](0027-external-read-api-boundary.md) — external read boundary; this ADR is money movement and does not use that read API auth model.
