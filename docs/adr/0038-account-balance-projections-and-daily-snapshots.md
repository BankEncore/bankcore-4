# ADR-0038: Account balance projections and daily snapshots

**Status:** Proposed  
**Date:** 2026-05-02  
**Decision Type:** Balance read model, EOD snapshot, and loan-ready projection architecture  
**Aligns with:** [ADR-0003](0003-posting-journal-architecture.md), [ADR-0004](0004-account-balance-model.md), [ADR-0012](0012-posting-rule-registry-and-journal-subledger.md), [ADR-0018](0018-business-date-close-and-posting-invariant.md), [ADR-0024](0024-customer-visible-history-and-statements.md), [module catalog](../architecture/bankcore-module-catalog.md)

---

## 1. Context

BankCORE currently computes deposit ledger and available balances from posted journal lines and active holds. This is correct for the current slice because the journal remains the authoritative financial record and there is no separate balance table that can drift from accounting truth.

As transaction volume grows, repeated journal aggregation becomes a poor fit for teller balance display, authorization checks, EOD processing, interest, average daily balance, and reporting. ADR-0004 already permits materialized ledger, available, collected, and daily balance projections when they remain derivable, rebuildable, and read-side only.

BankCORE also needs a pattern that can extend to loans. Loan balances will not share the same components as deposits: principal, accrued interest, fees, escrow, delinquency, and payoff views need different semantics. The shared design should be a projection and snapshot contract, not one ambiguous balance table.

---

## 2. Decision

Adopt a phased account balance architecture:

```text
Journal remains financial truth
        ↓
Domain-owned current balance projection
        ↓
Reporting-owned daily balance snapshots
        ↓
Interest, ADB, statements, reporting
```

The projection may become authoritative for fast operational reads after implemented, but it is never authoritative for accounting truth. The journal and applicable operational records remain the rebuild source.

For the first implementation:

- **Deposits first:** `Accounts` owns the current deposit account balance projection because account identity, holds, restrictions, and authorization-facing balances are account state.
- **Reporting snapshots:** `Reporting` owns daily balance snapshots and materialization services, per the module catalog.
- **Loan ready:** future `Loans` services define loan-specific projection components; `Reporting` snapshots must support account-domain/type metadata so loan rows can be added without forcing deposits and loans into one balance formula.

---

## 3. Ownership

| Concern | Owner | Rule |
| --- | --- | --- |
| Journal entries and lines | `Core::Ledger` / `Core::Posting` | Source of financial truth. |
| Deposit current projection | `Accounts` | Rebuildable operational read model for deposit account balances. |
| Deposit availability formula | `Accounts` now, future `Limits` if policy becomes broader | Must be centralized in a resolver, not controllers. |
| Daily balance snapshots | `Reporting` | Read-side historical projection and extract basis. |
| Deposit statements and deposit interest consumers | `Deposits` | Consume projections/snapshots; do not mutate ledger truth. |
| Future loan balance components | `Loans` | Loan-specific servicing projection semantics. |

---

## 4. Deposit current projection

Add an `Accounts`-owned table in a later implementation slice:

```text
deposit_account_balance_projections
```

Required fields:

```text
deposit_account_id
ledger_balance_minor_units
hold_balance_minor_units
available_balance_minor_units
collected_balance_minor_units
last_journal_entry_id
last_operational_event_id
as_of_business_date
last_calculated_at
stale
stale_from_date
calculation_version
created_at
updated_at
```

Initial formula:

```text
available_balance = ledger_balance - active_holds
```

`collected_balance_minor_units` remains nullable or omitted until a funds-availability model exists.

---

## 5. Transactional update rule

Projection updates must happen in the same database transaction as posting. The invariant is:

```text
Either journal + projection both update,
or neither update.
```

`Core::Posting::Commands::PostEvent` should create the posting batch, journal entry, and journal lines, then call a centralized `Accounts` projection updater before commit. Posting rule modules must not update projections directly.

Projection update steps for deposit-affecting entries:

1. Identify journal lines for deposit subledger GL `2110` with `deposit_account_id`.
2. Lock the projection row for each affected account.
3. Apply signed ledger delta:
   - credit `2110` increases deposit ledger balance;
   - debit `2110` decreases deposit ledger balance.
4. Recompute hold total and available balance through the resolver.
5. Store last journal entry, operational event, business date, calculation version, and timestamp.

If projection update fails, the posting transaction must roll back.

---

## 6. Hold and availability invalidation

Holds change available balance without changing ledger balance. Hold lifecycle commands must update or refresh the projection inside the same transaction that changes hold state:

- `Accounts::Commands::PlaceHold`
- `Accounts::Commands::ReleaseHold`
- future hold expiration processing

Availability must be calculated by one resolver. Controllers, teller previews, and authorization checks must not embed alternate formulas.

Future formula inputs may include account restrictions, collected funds rules, overdraft limits, channel-specific authorization holds, or product policy. Such formula changes require a `calculation_version` bump and rebuild/reconciliation plan.

---

## 7. Daily balance snapshots

Add a `Reporting`-owned daily snapshot model in a later implementation slice.

Logical contract:

```text
account_domain
account_type
account_id
as_of_date
balance_components
source
calculation_version
created_at
updated_at
```

For the deposit slice, explicit fields are preferred:

```text
ledger_balance_minor_units
hold_balance_minor_units
available_balance_minor_units
collected_balance_minor_units
```

Loan rows may later use loan-specific components. The design must preserve a clear component schema/version rather than storing one generic ambiguous `balance`.

The implemented Reporting contract reserves account metadata for both current and future account domains:

| Account domain | Account type | Component owner | Implementation status |
| --- | --- | --- | --- |
| `deposits` | `deposit_account` | `Accounts` projection + `Deposits` consumers | Implemented in this slice. |
| `loans` | `loan_account` | Future `Loans` projection and servicing rules | Reserved only; no loan servicing implementation. |

`daily_balance_snapshots` may identify future loan rows by domain/type, but BankCORE must not create production loan snapshots until a `Loans` implementation defines the loan projection components, calculation version, rebuild rules, and posting/servicing consumers. Deposit snapshot fields remain explicit in this slice; loan-specific principal, interest, escrow, fee, delinquency, and payoff components require a follow-up Loans ADR or ADR addendum before use.

---

## 8. EOD integration

Normal business-date close should materialize daily snapshots before advancing the open business date:

1. EOD readiness passes.
2. Select accounts requiring snapshots for the closing date.
3. Copy current projection values into daily snapshots.
4. Carry forward missing calendar dates where required.
5. Run reconciliation checks or record snapshot materialization evidence.
6. Advance the business date.

If required snapshots cannot be materialized, close should fail rather than advancing with incomplete historical balance data.

This ADR does not introduce backdated posting, day reopen, or closed-day mutation. ADR-0018 open-day posting remains in force.

---

## 9. Rebuild and reconciliation

Every projection must be rebuildable from authoritative data:

- posted `journal_lines` for ledger truth;
- active and historical hold records for availability inputs;
- explicit policy/configuration state used by the resolver.

Required services for implementation:

- rebuild one deposit projection from journal and hold truth;
- detect drift between projection and journal-derived truth;
- mark stale projections or snapshots when formulas change;
- record rebuild evidence and calculation version.

Reconciliation must report drift. Automatic correction should be an explicit rebuild command, not a silent side effect of ordinary reads.

Implementation hardening:

- `Accounts::Queries::DepositBalanceProjectionDrift` remains a read-only report.
- `Accounts::Commands::MarkDepositBalanceProjectionStale` is the explicit drift response: it marks the projection stale and creates `deposit_balance_rebuild_requests` evidence.
- `Accounts::Commands::RebuildDepositBalanceProjection` repairs the projection and records completed rebuild evidence.
- `Accounts::Commands::MarkDepositBalanceProjectionsStaleForVersion` marks projections stale when their `calculation_version` no longer matches the active formula version.
- New deposit accounts create a zero-balance projection during account opening; first posting and EOD materialization still retain create-under-lock fallbacks for legacy/missing rows.
- `Reporting::Commands::MarkDailyBalanceSnapshotsStaleForVersion` marks historical snapshots stale when their formula version is no longer current.
- `daily_balance_snapshots` are idempotent by account domain, account id, date, source, and calculation version so a future formula version can materialize a distinct row instead of overwriting historical evidence.

---

## 10. Worked examples

### 10.1 Deposit posting

Input event:

```json
{
  "event_type": "deposit.accepted",
  "source_account_id": 42,
  "amount_minor_units": 10000,
  "currency": "USD"
}
```

Posting outline:

```text
Dr 1110 Cash                         100.00
Cr 2110 Customer DDA, account 42      100.00
```

Projection effect:

```text
ledger_balance_minor_units += 10000
hold_balance_minor_units = active holds sum
available_balance_minor_units = ledger - active holds
last_operational_event_id = deposit event id
last_journal_entry_id = created journal entry id
```

### 10.2 Hold placement

Input event:

```json
{
  "event_type": "hold.placed",
  "source_account_id": 42,
  "amount_minor_units": 2500,
  "currency": "USD"
}
```

Posting outline:

```text
No GL posting.
```

Projection effect:

```text
ledger_balance_minor_units unchanged
hold_balance_minor_units += 2500
available_balance_minor_units = ledger - active holds
last_operational_event_id = hold event id
```

### 10.3 Future loan payment

Loan projections will follow the same contract, but not the same components. A future loan payment might update:

```text
principal_balance_minor_units
interest_due_minor_units
fees_due_minor_units
payoff_balance_minor_units
```

Those semantics belong to `Loans`; daily snapshots should carry typed/versioned components so ADB-style deposit calculations and loan payoff calculations do not share one formula.

The reserved Reporting identity would be:

```text
account_domain = loans
account_type   = loan_account
account_id     = <future loan account id>
```

This identity is not enough to produce a loan balance. A future `Loans` slice must define the projection owner, component schema, materializer, reconciliation method, and consumer rules before any loan snapshot rows are used operationally.

---

## 11. Non-goals

- Implementing the projection tables in this ADR-only slice.
- Replacing journal truth with projection truth.
- Backdated posting, day reopen, or closed-day mutation.
- Full Reg CC collected funds logic.
- Loan servicing implementation.
- Caching average daily balance as a standing account field.

---

## 12. Consequences

**Positive**

- Faster teller, branch, and authorization reads once implemented.
- Cheaper EOD: daily snapshots become copy/materialization operations for most accounts.
- Clear historical basis for statements, ADB, interest, and reporting.
- Rebuild and reconciliation rules are explicit.
- Loan balances can adopt the same pattern without sharing deposit-specific math.

**Negative**

- More moving parts than compute-on-read.
- Requires disciplined invalidation paths for posting, holds, policy changes, and future correction flows.
- Requires reconciliation and rebuild operations before projections can be trusted for operational reads.
- EOD close gains another consistency dependency.

---

## 13. Implementation sequence

1. Add deposit current projection schema and model.
2. Add an `Accounts` projection updater called transactionally from `PostEvent`.
3. Refactor available-balance math into a resolver.
4. Refresh projection values from hold lifecycle commands.
5. Migrate teller, branch, and authorization reads to projection-backed services.
6. Add rebuild and reconciliation services.
7. Add `Reporting` daily snapshots and materialization.
8. Integrate snapshot materialization into business-date close.
9. Move closed-period statement and future interest/ADB consumers to daily snapshots.
10. Extend the pattern to loans in a separate `Loans` implementation slice.

---

## 14. Related documents

- [ADR-0003: Posting & journal architecture](0003-posting-journal-architecture.md)
- [ADR-0004: Account & balance model](0004-account-balance-model.md)
- [ADR-0012: Posting rule registry and journal subledger](0012-posting-rule-registry-and-journal-subledger.md)
- [ADR-0018: Business date close and open-day posting invariant](0018-business-date-close-and-posting-invariant.md)
- [ADR-0024: Customer-visible history and statements](0024-customer-visible-history-and-statements.md)
- [BankCORE module catalog](../architecture/bankcore-module-catalog.md)
