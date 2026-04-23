# Override requested (`override.requested`)

## Summary

Records that an operator **requested** an exception to normal policy (e.g. large cash variance approval, reversal authorization, limit override). This is a **workflow / audit** artifact; it does not by itself post to the GL.

## Registry

| Field | Value |
| ----- | ----- |
| **`event_type`** | `override.requested` |
| **Category** | Operational (ADR-0002 §5.3) |
| **Phase** | Optional Phase 1; use when you need a durable request row separate from RBAC logs. |

## Semantics

- **Must** identify **what** is being overridden (session close with variance, specific operational event id, hold policy, etc.) via `reference_id` / JSON metadata when those columns exist.
- **Does not** grant authority by itself; **`override.approved`** (or session-level supervisor fields) represents acceptance.

## Persistence

| Column / concept | Required | Notes |
| ---------------- | -------- | ----- |
| `event_type` | Yes | `override.requested`. |
| `status` | Yes | Often stays **`pending`** until paired approval or **expires** if you add expiry later; alternatively `posted` when request is merely recorded. **Define one vocabulary** for this type. |
| `channel` | Yes | |
| `idempotency_key` | Yes | If API-driven. |
| `reference_id` | Recommended | Target entity (session id, event id, etc.) when column exists. |
| `actor_id` | Recommended | Requesting operator: FK → **`operators`**, set from authenticated operator on teller **`POST /teller/overrides`** ([ADR-0015](../adr/0015-teller-workspace-authentication.md)). |

## Lifecycle

**Recommended:** `pending` until superseded by `override.approved` or rejection; avoid overloading `posted` unless it only means “request recorded.”

## Posting

- **No.**

## Idempotency

- Fingerprint includes override **kind** and **target reference** so the same key cannot request a different override.

## Reversals

- N/A; use explicit cancel/expire event if needed later.

## Relationships

- May reference **`teller_session_id`**, **`operational_events`** (reversal target), etc., via `reference_id` or dedicated FKs when added.

## Module ownership

- **`Teller`** / **`Workflow`** per product choice; keep **financial posting** out of this path.

## References

- [ADR-0002](../adr/0002-operational-event-model.md) §5.3
- [ADR-0015](../adr/0015-teller-workspace-authentication.md) — teller headers and `actor_id`

## Examples

```json
{
  "event_type": "override.requested",
  "channel": "teller",
  "idempotency_key": "ovr-req-session-7-variance",
  "reference_id": "teller_session:7"
}
```
