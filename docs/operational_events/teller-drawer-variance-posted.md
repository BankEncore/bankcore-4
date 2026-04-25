# `teller.drawer.variance.posted`

## Summary

Records a **GL-only adjustment** for **non-zero teller drawer cash variance** when the institution enables automatic posting ([ADR-0020](../adr/0020-teller-drawer-variance-gl-posting.md)). The authoritative variance amount remains on **`teller_sessions.variance_minor_units`**; this event is the **ledger intent** for **1110** / **5190**.

## Registry

| Field | Value |
| ----- | ----- |
| **`event_type`** | `teller.drawer.variance.posted` |
| **Category** | financial |
| **Phase** | Optional Phase 2 (product flag) |
| **Lifecycle** | `pending_to_posted` |
| **Allowed channels** | `system` |
| **Financial impact** | `optional_gl` |
| **Customer visible** | No |
| **Statement visible** | No |
| **Payload schema** | `docs/operational_events/teller-drawer-variance-posted.md` |
| **Support search keys** | `teller_session_id`, `reference_id` |

## Semantics

- **Only** created from **`Teller::Services::PostDrawerVarianceToGl`** when **`TELLER_POST_DRAWER_VARIANCE_TO_GL`** is enabled and the session is **`closed`** with **non-zero** variance.
- **`channel` must be `system`**. Teller JSON must not be used to inject this type (validated in **`RecordEvent`**).
- **`amount_minor_units`** is **signed** and must equal **`teller_sessions.variance_minor_units`** (negative = physical cash **short** vs expected; positive = **over**).
- **One** operational event per **`teller_session_id`** (enforced by deterministic idempotency key and duplicate guard).

## Persistence

| Column | Required | Notes |
| ------ | -------- | ----- |
| `event_type` | Yes | `teller.drawer.variance.posted` |
| `channel` | Yes | `system` |
| `idempotency_key` | Yes | `drawer-variance-{teller_session_id}` |
| `amount_minor_units` | Yes | Signed non-zero integer (minor units) |
| `currency` | Yes | `USD` |
| `teller_session_id` | Yes | FK to closed session |
| `source_account_id` | No | **null** (no DDA) |
| `business_date` | Yes | Current open business date when recorded |
| `actor_id` | No | Supervisor id when posted after **`ApproveSessionVariance`**; otherwise null |

## Lifecycle

`pending` → **`PostEvent`** → `posted`. No supervisor gate on **`PostEvent`** itself; session variance workflow already applied per [ADR-0014](../adr/0014-teller-sessions-and-control-events.md).

## Posting

| Seq | GL | Side | `deposit_account_id` |
| --- | --- | ---- | --------------------- |
| Shortage (amount &lt; 0) | 5190 | debit | null |
| | 1110 | credit | null |
| Overage (amount &gt; 0) | 1110 | debit | null |
| | 5190 | credit | null |

Magnitude on each line = **`abs(amount_minor_units)`**.

## Idempotency

Unique **`(channel, idempotency_key)`** with **`channel: system`**. Fingerprint includes `event_type`, `channel`, `idempotency_key`, signed `amount_minor_units`, `currency`, `teller_session_id`.

## Reversals

**Not** reversible via **`posting.reversal`** in MVP ([ADR-0020](../adr/0020-teller-drawer-variance-gl-posting.md)).

## Relationships

Strong link to **`teller_sessions`** via **`teller_session_id`**. No deposit account.

## Module ownership

- **`Teller::Services::PostDrawerVarianceToGl`** — orchestration after close / approve.
- **`Core::OperationalEvents::Commands::RecordEvent`** — validation and persistence.
- **`Core::Posting::PostingRules::TellerDrawerVariancePosted`** — legs.

## References

- [ADR-0020](../adr/0020-teller-drawer-variance-gl-posting.md)
- [ADR-0014](../adr/0014-teller-sessions-and-control-events.md)
- [teller-session-closed.md](teller-session-closed.md)

## Examples

**Shortage $1.00** (`variance_minor_units: -100`):

```json
{
  "event_type": "teller.drawer.variance.posted",
  "channel": "system",
  "idempotency_key": "drawer-variance-42",
  "amount_minor_units": -100,
  "currency": "USD",
  "teller_session_id": 42
}
```

**Posting:** Dr 5190 / Cr 1110 for **100** minor units.
