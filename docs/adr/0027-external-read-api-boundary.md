# ADR-0027: External read API boundary

**Status:** Proposed  
**Date:** 2026-04-25  
**Aligns with:** [ADR-0015](0015-teller-workspace-authentication.md), [ADR-0025](0025-internal-workspace-ui.md), [ADR-0026](0026-branch-csr-servicing.md), [ADR-0019](0019-event-catalog-and-fee-events.md), [roadmap](../roadmap.md) Phase 4.6

---

## 1. Context

Phase 4.6 introduces read-only external API contracts for customer, partner, or fintech consumers. BankCORE already has internal staff surfaces:

- `/teller` JSON APIs authenticated by `X-Operator-Id`
- Branch/Ops/Admin HTML workspaces authenticated by internal browser sessions

Those staff trust boundaries must not become external API authentication. External clients need their own identity, authorization, redaction, rate-limit, audit, and response contracts before any customer or partner reads ship.

---

## 2. Decision

Phase 4.6 will introduce a separate read-only API namespace, initially planned as `/api/v1`, implemented by `Api::V1::*` controllers. It will reuse existing domain query objects but expose only explicitly serialized, customer/partner-safe fields.

The first implementation must be ADR-approved before code ships. This ADR defines the target boundary and constraints; it does not yet implement the API.

### 2.1 Authentication and client identity

External API requests must authenticate as an API client or subject that is separate from `Workspace::Models::Operator`.

Rules:

- Do not use Branch/Ops/Admin Rails session cookies.
- Do not use `/teller` `X-Operator-Id`.
- Do not accept role, customer, party, or account authority claims from request params.
- Store only hashed API credentials or references; never persist raw bearer secrets.
- Every successful request must resolve to a durable client identifier suitable for audit.

The first implementation may use opaque bearer tokens tied to an API-client table, or another reviewed mechanism. OAuth/JWT/mTLS may be added later, but must preserve the same resolved-client and scoped-access contract.

### 2.2 Authorization and scoping

External clients may read only resources explicitly granted to their client/subject scope.

Initial scope model:

- account-scoped reads are permitted only for accounts linked to the resolved client or subject
- event reads must be filtered to the allowed account set
- product reads may expose only product summary fields that are already customer/partner safe
- support/internal identifiers are omitted unless explicitly listed in the response contract

### 2.3 Redaction and visibility

External APIs must not reuse staff JSON payloads verbatim. Controllers should call domain queries and then pass results through API serializers or presenters.

Event responses must respect `Core::OperationalEvents::EventCatalog`:

- external account activity may include only customer-visible or statement-visible event types, depending on endpoint intent
- support-only events remain internal unless a later ADR promotes them
- free-form staff notes, internal audit notes, operator ids, and posting/journal ids are internal by default

### 2.4 Rate limits and pagination

Every collection endpoint must define:

- maximum date range
- default and maximum page size
- cursor semantics
- stable sort order
- error shape for malformed ranges or cursor values

Initial collection endpoints should inherit current domain-query constraints where appropriate, such as `Core::OperationalEvents::Queries::ListOperationalEvents` date-range and limit rules.

### 2.5 Audit attribution

External reads must leave enough evidence to answer who accessed what and when:

- resolved API client id
- optional resolved subject/customer id if applicable
- endpoint name
- request id
- response status
- scoped account or product identifiers when available
- timestamp

Detailed audit persistence can be an API-access audit table or structured logs, but the chosen approach must be testable and queryable for support.

### 2.6 Response contracts

Responses should use a stable envelope:

```json
{
  "data": {},
  "meta": {
    "request_id": "req_...",
    "current_business_on": "2026-04-25"
  },
  "links": {}
}
```

Errors should use:

```json
{
  "error": "invalid_request",
  "message": "business_date_from and business_date_to are both required",
  "request_id": "req_..."
}
```

---

## 3. Planned Read Contracts

Initial Phase 4.6 implementation may plan these read-only routes:

| Route | Backing query | Notes |
| --- | --- | --- |
| `GET /api/v1/deposit_accounts/:id` | `Accounts::Queries::DepositAccountProfile` | Redacted account summary, balances, product summary, and safe hold summary. |
| `GET /api/v1/deposit_accounts/:id/activity` | `Deposits::Queries::StatementActivity` | Ledger-derived and customer-visible no-GL activity for a bounded date range. |
| `GET /api/v1/deposit_accounts/:id/statements` | `Deposits::Queries::ListDepositStatements` | Statement metadata only; no PDF/document delivery. |
| `GET /api/v1/deposit_accounts/:id/events` | `Core::OperationalEvents::Queries::ListOperationalEvents` | Account-scoped event history filtered by catalog visibility. |
| `GET /api/v1/deposit_products/:id` | Products queries/resolver | Customer-safe product summary and active behavior labels only. |

---

## 4. Non-goals

Phase 4.6 does **not** add:

- external writes or idempotent write APIs
- ACH, wire, card, ATM, or partner money movement
- customer portal session auth
- Branch/Ops/Admin browser reuse
- `/teller` header reuse
- statement PDF rendering, document storage, notifications, or delivery preferences
- broad reporting snapshots or materialized balances
- exposure of journal entries, posting batches, GL accounts, staff notes, or internal operator ids

---

## 5. Consequences

Positive:

- External APIs can reuse trusted domain queries without leaking staff payloads.
- Event visibility metadata from Phase 4.2 becomes a guardrail for customer/partner history.
- Future money-moving channels get a separate auth/audit foundation.

Negative:

- A separate API-client identity model and serializers add work before the first endpoint ships.
- Redaction tests are required for every endpoint and event visibility class.

Neutral:

- The existing `/teller`, Branch, Ops, and Admin surfaces remain unchanged.
