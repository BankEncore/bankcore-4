# Compensating reversal (financial correction)

## Summary

Describes the **pattern** for undoing a **posted financial** operational event **without** mutating the original row. A **new** operational event is recorded, linked to the original via reversal FKs, and `PostEvent` creates a **compensating** journal (mirror debits/credits) per ADR-0002 §6 and ADR-0003 reversal postings.

This document is **pattern-first**. The canonical **`event_type`** string for reversals is an open product decision (see [roadmap §12](../roadmap.md)); options include:

- **Per original type:** e.g. `deposit.accepted.reversal`
- **Generic:** e.g. `financial_event.reversed` with payload identifying original event id and rule selection

Implementation uses a **generic** `posting.reversal` plus `Core::OperationalEvents::Commands::RecordReversal`; posting rules mirror the original journal ([ADR-0012](../adr/0012-posting-rule-registry-and-journal-subledger.md)).

## Registry

| Field | Value |
| ----- | ----- |
| **`event_type`** | **`posting.reversal`** — generic compensating row; original id in **`reversal_of_event_id`**. |
| **Category** | Financial (produces GL) |
| **Phase** | Phase 1 (reversal path + linkage + two journals). |
| **Lifecycle** | `pending_to_posted` |
| **Allowed channels** | `teller`, `branch`, `api`, `batch` |
| **Financial impact** | `gl_posting` |
| **Customer visible** | Yes |
| **Statement visible** | Yes |
| **Payload schema** | `docs/operational_events/compensating-reversal.md` |
| **Support search keys** | `source_account_id`, `destination_account_id`, `reversal_of_event_id`, `actor_id` |

## Semantics

- **Original** event must already be **`posted`** with a successful journal.
- Reversal **never** changes `status` on the original row from `posted`.
- **“Was reversed”** is derived from `reversal_of_event_id` / `reversed_by_event_id` (when columns exist) and/or presence of the compensating posted event (ADR-0002 §3.2, §6).
- **At most one** business-meaningful compensating reversal per original unless a future ADR explicitly allows partial/multi-step reversals.

## Persistence

**New reversal row:**

| Column / concept | Required | Notes |
| ---------------- | -------- | ----- |
| `event_type` | Yes | Chosen reversal type. |
| `reversal_of_event_id` | Yes | FK → original `operational_events.id`. |
| `status` | Yes | `pending` → `posted` after compensating journal commits. |
| `amount_minor_units` | Typically | Matches original reversal magnitude for full reversal MVP. |
| `currency`, `channel`, `idempotency_key` | Yes | Same idempotency rules as other events. |
| `source_account_id` / `destination_account_id` | As needed | Often mirror original for posting rule resolution. |
| `actor_id` | Optional | Nullable FK → **`operators`**. On **`POST /teller/reversals`**, set from **`X-Operator-Id`**; HTTP requires **supervisor** ([ADR-0015](../adr/0015-teller-workspace-authentication.md)). |

**Original row (updates allowed only for linkage fields, not business mutation):**

| Column | Notes |
| ------ | ----- |
| `reversed_by_event_id` | Set to the compensating event id when reversal posts (ADR-0002 §4.4). |

> Journal-level links `reverses_journal_entry_id` / `reversing_journal_entry_id` on `journal_entries` (ADR-0010 §7) should align with the compensating entry; implementation must respect DB immutability triggers on posted journals.

## Lifecycle

1. Record reversal event **`pending`** (teller JSON: **supervisor** gate before `RecordReversal`; see [ADR-0015](../adr/0015-teller-workspace-authentication.md)).
2. `PostEvent` writes compensating lines; batch **`posted`**; event **`posted`**.
3. Original remains **`posted`**; linkage columns record the relationship.

## Posting

- **Yes** — compensating legs are the **mirror** of the original journal for a full reversal (same amounts, debits become credits and vice versa on the same GL / subledger accounts).
- **Supervisor:** Teller workspace enforces supervisor before recording the reversal event ([ADR-0015](../adr/0015-teller-workspace-authentication.md)); command layer does not re-check for MVP.

## Idempotency

- Reversal submission **must** be idempotent: same `(channel, idempotency_key)` must not create a second posted compensation for the same original.

## Reversals

- A reversal of a reversal is out of scope for MVP unless explicitly specified; normally **chain** stops at one compensating event.

## Relationships

- **`reversal_of_event_id`** → original financial event.
- Optional: same `teller_session_id` as original for audit.

## Module ownership

- **Record:** `Core::OperationalEvents` (dedicated command recommended: e.g. `RecordReversal`).
- **Post:** `Core::Posting` with a rule keyed off reversal `event_type` and/or metadata pointing at original.

## References

- [ADR-0002](../adr/0002-operational-event-model.md) §6, §8.1
- [ADR-0003](../adr/0003-posting-journal-architecture.md) — reversal postings
- [ADR-0010](../adr/0010-ledger-persistence-and-seeded-coa.md) §7 — journal reversal FKs
- [ADR-0015](../adr/0015-teller-workspace-authentication.md) — teller `X-Operator-Id`, supervisor gate on reversals

## Examples

**Conceptual:** Original `deposit.accepted` posted Dr 1110 / Cr 2110(acct 42). Compensating reversal posts **Dr 2110(acct 42) / Cr 1110** for the same minor units.
