# Override approved (`override.approved`)

## Summary

Records that a **supervisor** (or role with equivalent authority) **approved** a previously requested exception. Pairs with [`override.requested`](override-requested.md) when both are modeled as operational events; alternatively approval may live only on `teller_sessions` until you need a separate audit row.

## Registry

| Field | Value |
| ----- | ----- |
| **`event_type`** | `override.approved` |
| **Category** | Operational (ADR-0002 §5.3) |
| **Phase** | Optional Phase 1 (supervisor gates for variance / reversal). |

## Semantics

- **Must** reference the request or target entity: link to `override.requested` event id, or `reference_id` pointing at session / event under approval.
- **Must** enforce RBAC: approver has **supervisor** (or configured) role; **must not** allow teller to approve their own material variance if policy forbids it.
- Grants **permission** for downstream commands to proceed (close session with variance, post reversal, etc.); the downstream command still performs the actual state/GL change.

## Persistence

| Column / concept | Required | Notes |
| ---------------- | -------- | ----- |
| `event_type` | Yes | `override.approved`. |
| `status` | Yes | Typically **`posted`** when approval is committed (audit finality). |
| `channel` | Yes | Often `teller` or `system`. |
| `idempotency_key` | Yes | |
| `reference_id` / request link | Yes | What was approved. |
| `actor_id` | Yes when available | Approving supervisor. |

## Lifecycle

Usually **single-step `posted`** on insert: approval is immediate once validated.

## Posting

- **No.**

## Idempotency

- Same approval request must not yield two distinct effective approvals; use idempotency or unique constraint on `(request_id, approver_id)` if modeled.

## Reversals

- Revoking approval is a separate policy story; not GL reversal.

## Relationships

- **`override.requested`:** logical predecessor when both exist as rows.
- **Session / reversal commands** consume this as a prerequisite.

## Module ownership

- **`Teller`** / **`Workflow`** with RBAC enforced at application boundary.

## References

- [ADR-0002](../adr/0002-operational-event-model.md) §5.3
- [roadmap.md](../roadmap.md) — Phase 1 supervisor approval

## Examples

```json
{
  "event_type": "override.approved",
  "channel": "teller",
  "idempotency_key": "ovr-appr-session-7-supervisor-12",
  "reference_id": "override_request:900"
}
```
