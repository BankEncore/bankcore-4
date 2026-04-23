# ADR-0013: Holds, available balance, and servicing operational events

**Status:** Accepted  
**Date:** 2026-04-23  
**Aligns with:** [ADR-0004](0004-account-balance-model.md), [ADR-0002](0002-operational-event-model.md)

---

## 1. Decision

- **`holds`** table is owned by **`Accounts`**. Active holds reduce **available** balance; they do not post GL journals.
- **`hold.placed`** / **`hold.released`** are persisted as `operational_events` rows with **`posted`** status at creation (no `PostEvent` path). Commands: **`Accounts::Commands::PlaceHold`** and **`Accounts::Commands::ReleaseHold`**.
- **Available** for authorization: `Accounts::Services::AvailableBalanceMinorUnits` = ledger on GL **2110** filtered by `journal_lines.deposit_account_id` minus active hold amounts ([ADR-0012](0012-posting-rule-registry-and-journal-subledger.md) subledger).

---

## 2. Consequences

- `withdrawal.posted` and `transfer.completed` **`RecordEvent`** reject when available &lt; amount.
