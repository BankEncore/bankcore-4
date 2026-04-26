# External Read API Contract Plan

Phase 4.6 implementation must follow [ADR-0027](adr/0027-external-read-api-boundary.md). This document captures the planned route and serializer shape; it is not an implementation.

## Namespace

Use a new `Api::V1` namespace mounted at `/api/v1`. Do not reuse:

- `/teller` routes or `X-Operator-Id`
- Branch/Ops/Admin session-cookie controllers
- staff-facing JSON response shapes

## Planned Controllers

| Controller | Routes | Purpose |
| --- | --- | --- |
| `Api::V1::DepositAccountsController` | `GET /api/v1/deposit_accounts/:id` | Account profile, balances, product summary, safe hold summary. |
| `Api::V1::DepositAccountActivitiesController` | `GET /api/v1/deposit_accounts/:deposit_account_id/activity` | Bounded account activity from statement activity. |
| `Api::V1::DepositAccountStatementsController` | `GET /api/v1/deposit_accounts/:deposit_account_id/statements` | Statement metadata only. |
| `Api::V1::DepositAccountEventsController` | `GET /api/v1/deposit_accounts/:deposit_account_id/events` | Account-scoped event history filtered by catalog visibility. |
| `Api::V1::DepositProductsController` | `GET /api/v1/deposit_products/:id` | Customer/partner-safe product summary. |

## Planned Serializers

Serializers or presenters should live under `app/controllers/api/v1/serializers/` or another ADR-approved API presentation namespace.

| Serializer | Backing data | Redaction rules |
| --- | --- | --- |
| `DepositAccountSerializer` | `Accounts::Queries::DepositAccountProfile` | Include account id/number/status/currency, ledger/available balances, product summary. Omit owner history unless scope allows it. |
| `AccountActivitySerializer` | `Deposits::Queries::StatementActivity` | Include date, description, amount, balance impact if available. Omit GL ids and staff-only operational metadata. |
| `StatementSerializer` | `Deposits::Queries::ListDepositStatements` | Include period, status, generated timestamps, and statement id. Omit PDF/document links until delivery scope exists. |
| `OperationalEventSerializer` | `Core::OperationalEvents::Queries::ListOperationalEvents` | Include only catalog-visible events and customer-safe fields. Omit posting batch ids, journal entry ids, operator ids, and staff notes. |
| `DepositProductSerializer` | Products queries/resolver | Include product code/name/currency and customer-safe behavior summaries. Omit internal rule ids unless contract explicitly allows them. |

## Envelope

All success responses should use:

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

Collections should include cursor metadata in `meta` or `links`, matching the backing query constraints.

## Validation Checklist

- Auth failure returns `401` and does not leak resource existence.
- Scope failure returns `404` or `403` per ADR-approved contract.
- Date ranges honor backing query maximums.
- Event endpoints apply `EventCatalog` customer/statement visibility.
- Every endpoint has redaction tests proving staff-only fields are absent.
