# ADR-0018: Business date close and open-day posting invariant

**Status:** Accepted  
**Date:** 2026-04-22  
**Aligns with:** [ADR-0016](0016-trial-balance-and-eod-readiness.md) (EOD readiness composition), [ADR-0011](0011-accounts-deposit-vertical-slice-mvp.md) (business date for participation and events), [roadmap Phase 2](../roadmap.md) “Business date close”, [module catalog](../architecture/bankcore-module-catalog.md) §6.4

---

## 1. Context

[ADR-0016](0016-trial-balance-and-eod-readiness.md) ships **read-only** trial balance and EOD readiness. The singleton **`core_business_date_settings.current_business_on`** could advance via **`AdvanceBusinessDate`** with **no** gates, and **`RecordEvent`** / **`RecordReversal`** / **`RecordControlEvent`** / hold commands accepted an explicit **`business_date`** without requiring it to match the open processing day—allowing backdating and future dating relative to the singleton.

Phase 2 needs a **supervised close** that advances the calendar **only** when ADR-0016 readiness is satisfied, and a **posting invariant** so new operational and hold activity is stamped only for the **current open business day**.

---

## 2. Decisions

### 2.1 Close business day (mutation)

- **Command:** **`Core::BusinessDate::Commands::CloseBusinessDate`**
- **Preconditions:** Inside a DB transaction, **`FOR UPDATE`** lock the singleton **`core_business_date_settings`** row. Resolve **`closing_on`** as **`current_business_on`** before advance. Optional HTTP body **`business_date`** (ISO date) **must equal** `closing_on` if supplied; otherwise reject (avoids accidental close of the wrong conceptual day).
- **EOD gate:** **`Teller::Queries::EodReadiness.call(business_date: closing_on)[:eod_ready]`** must be **true** (same composition as ADR-0016: balanced journal totals for that date, no open or pending-supervisor teller sessions institution-wide, no **pending** operational events on that **business_date**). If false, raise **`Core::BusinessDate::Errors::EodNotReady`** carrying the readiness payload fields needed for HTTP **422** responses.
- **Effect:** Set **`current_business_on`** to **`closing_on + 1 calendar day`** (same increment as legacy **`AdvanceBusinessDate`**).
- **Audit:** Append-only **`core_business_date_close_events`**: **`closed_on`** (date closed), **`closed_at`**, optional **`closed_by_operator_id`** (FK to **`operators`** when closed via Teller supervisor). Unique index on **`closed_on`** so each calendar close is recorded once.

**Note:** **`Core`** already references **`Teller::Models`** for teller session validation on financial events; this command adds **`Core` → `Teller::Queries`** for the close gate. A future refactor could extract a Core-owned readiness query if dependency direction is tightened.

### 2.2 Posting invariant (open day only)

- **Service:** **`Core::BusinessDate::Services::AssertOpenPostingDate.call!(date:)`** — raises **`Core::BusinessDate::Errors::InvalidPostingBusinessDate`** unless **`date == Core::BusinessDate::Services::CurrentBusinessDate.call`**.
- **Callers:** **`RecordEvent`**, **`RecordReversal`**, **`RecordControlEvent`**, **`Accounts::Commands::PlaceHold`**, **`Accounts::Commands::ReleaseHold`** — after resolving the effective **`Date`** (explicit `business_date` or default to current), assert equality. **`business_date` omitted** remains valid (defaults to current).

### 2.3 Unsafe advance

- **`Core::BusinessDate::Commands::AdvanceBusinessDate`** is **disallowed outside `Rails.env.test?`** (raises **`Core::BusinessDate::Errors::UnsafeAdvanceDisallowed`**). Production and development operators must use **`CloseBusinessDate`** after EOD readiness. Tests may still advance without full EOD fixtures.

### 2.4 HTTP (Teller workspace)

- **`POST /teller/business_date/close`** — **`X-Operator-Id`** required; **`require_supervisor!`** (same posture as reversals). Optional JSON body **`{ "business_date": "YYYY-MM-DD" }`** must match current open day when present.
- **Success:** **201** with **`closed_on`**, **`previous_business_on`** (same as `closed_on`), **`current_business_on`** (new open day).
- **Errors:** **422** `eod_not_ready` + readiness fields; **422** `invalid_request` for date mismatch; **403** supervisor; **401** missing operator.

### 2.5 Stricter EOD read shape (read-only)

- **`Teller::Queries::EodReadiness`** adds **`current_business_on`** (ISO string) and **`posting_day_closed`**: **true** when the requested **`business_date` < current** open day (historical day—posting is no longer open for that calendar date under the singleton model). No change to ADR-0016 supervisor policy on **GET** reports.

---

## 3. Non-goals

Multi-branch business dates, day **reopen**, GL **period** locks beyond this invariant, balance **snapshots**, changing **`PostEvent`** leg rules.

---

## 4. Consequences

**Positive:** Closed days cannot receive new stamped **`business_date`** activity via routine APIs; close is auditable and gated on the same readiness operators already review.

**Negative:** **`Core`** depends on **`Teller::Queries`** for close; **`AdvanceBusinessDate`** is no longer a production escape hatch.

---

## 5. Related ADRs

- [ADR-0016](0016-trial-balance-and-eod-readiness.md) — readiness definition  
- [ADR-0011](0011-accounts-deposit-vertical-slice-mvp.md) — **`CurrentBusinessDate`** defaults  
- [ADR-0015](0015-teller-workspace-authentication.md) — operator headers and supervisor role
