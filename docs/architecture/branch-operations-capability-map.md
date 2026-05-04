# Branch operations capability map

**Status:** Draft  
**Last reviewed:** 2026-04-28  
**Companion to:** [BankCORE branch operations roadmap](../roadmap-branch-operations.md), [master-transaction-capability-registry.md](master-transaction-capability-registry.md) (capability codes ↔ `event_type` / F1–F17), [303-bank-transaction-capability-taxonomy.md](../concepts/303-bank-transaction-capability-taxonomy.md) (**bank-wide** capability families—not teller-owned).

This map connects branch activities to BankCORE module ownership, operational events, posting behavior, read models, and audit controls. It is a planning and sequencing artifact only. It does **not** introduce new event types, posting rules, GL mappings, business-date behavior, or table ownership by itself.

Authoritative boundaries remain in the [module catalog](bankcore-module-catalog.md), [MVP vs Full System](../concepts/01-mvp-vs-core.md), and accepted ADRs.

---

## 1. How to Use This Map

Use this document when selecting a branch-operations slice. For each activity, confirm:

- the primary owning module
- whether the activity records an operational event, creates a posting, creates a domain audit row, or is read-only
- which command/query surface should own the behavior
- what controls must run before the action completes
- whether existing ADRs are sufficient or a new ADR is required

When a slice changes financial effects, posting rules, reversals, GL ownership, external rail contracts, product behavior, or durable approval workflow, add or update an ADR before implementation.

---

## 2. Cross-Cutting Rules

1. Controllers under `branch`, `teller`, `ops`, and `admin` are workspaces. They orchestrate commands and queries; they do not own domain state.
2. `Core::OperationalEvents` records durable business facts and audit context.
3. `Core::Posting` converts eligible operational events into balanced accounting effects.
4. `Core::Ledger` remains financial truth.
5. `Accounts`, `Party`, `Products`, `Deposits`, `Cash`, `Workflow`, `Workspace`, and `Organization` own their respective state and controls.
6. `operating_unit_id` is operational attribution and authorization scope. It is not a branch ledger, branch business date, or legal entity.
7. Corrections are explicit forward records: reversals, releases, expirations, voids, replacements, or superseding rows.
8. **Authorized surfaces** (Branch HTML teller line, teller supervisor, CSR, and JSON `/teller`) orchestrate access; **capabilities** gate categories of action. Surfaces do not own domain state—see [ADR-0037](../adr/0037-internal-staff-authorized-surfaces.md).

---

## 3. Capability Summary

| Capability area | MVP posture | Primary owner | Financial posting | ADR coverage |
| --- | --- | --- | --- | --- |
| Party creation and basic CIF | MVP | `Party` | No | ADR-0009 |
| Deposit account opening | MVP | `Accounts` | No direct posting | ADR-0011, ADR-0017 |
| Teller deposits, withdrawals, transfers | MVP | `Core::OperationalEvents`, `Core::Posting`, `Teller` | Yes | ADR-0002, ADR-0012, ADR-0014 |
| Holds and available balance | MVP / shipped depth | `Accounts` | No GL for holds | ADR-0004, ADR-0013 |
| Fees and fee waivers | MVP / shipped depth | `Deposits`, `Accounts`, `Core::Posting` | Yes for `fee.assessed` / `fee.waived` | ADR-0019, ADR-0022 |
| Reversals | MVP | `Core::OperationalEvents`, `Core::Posting` | Yes | ADR-0002, ADR-0012 |
| Teller sessions and variance | MVP | `Teller` | Optional GL variance | ADR-0014, ADR-0020 |
| Trial balance and EOD readiness | MVP | `Teller`, `Core::Ledger`, `Core::BusinessDate` | Read-only | ADR-0016, ADR-0018 |
| Branch customer/account servicing | Near-term / partially shipped | `Branch` workspace over `Party`, `Accounts`, `Deposits` | Only for financial servicing events | ADR-0025, ADR-0026 |
| Operating-unit branch scope | Near-term / shipped first slice | `Organization`, `Workspace` | No | ADR-0032 |
| Cash inventory and vault/drawer custody | Near-term / shipped foundation | `Cash` | No GL for internal custody movement; GL only for approved variances and ADR-0035 shipment receipts | ADR-0031, ADR-0035 |
| Product behavior engine | Later / partial resolver shipped | `Products`, `Deposits`, `Accounts` | Indirect through event/posting | ADR-0030 |
| Negotiable instruments | Later | TBD, likely `Instruments` | Yes for issuance/payment lifecycle | ADR needed |
| External payments and rails | Later / ACH receipt slice shipped | `Integration` | Yes where settlement posts | ADR-0028, more ADRs needed |
| Compliance cases and regulatory reporting | Later | `Compliance`, `Documents`, `Reporting` | Usually no direct posting | ADRs needed per slice |

---

## 4. Phase 1: Branch-Safe Transaction MVP

These capabilities answer the first branch question: can staff open accounts, move money safely, prove the books, and close the day?

| Branch activity | Owner | Command/query surface | Operational event / audit record | Posting behavior | Read model / evidence | Controls |
| --- | --- | --- | --- | --- | --- | --- |
| Create party / basic customer record | `Party` | `Party::Commands::CreateParty`, Party search/profile queries | Usually no operational event in current slice | None | Customer search and profile views | Required fields, identity data shape, audit timestamps |
| Open deposit account | `Accounts` | `Accounts::Commands::OpenAccount` | No financial event by itself | None | Branch deposit account profile | Existing party, product resolution, ownership invariants, business date |
| Open teller session | `Teller` | `Teller::Commands::OpenSession` | Table-first teller session row | None | Branch dashboard / session views | Active operator, operating unit, drawer/session uniqueness |
| Accept cash deposit | `Core::OperationalEvents`, `Teller` | `RecordEvent`, `PostEvent` | `deposit.accepted` | Dr 1110 / Cr 2110 | Event detail, receipt, journal trace | Open account, idempotency, current business date, open teller session where required |
| Post withdrawal | `Core::OperationalEvents`, `Accounts`, `Teller` | `Accounts::Commands::AuthorizeDebit`, `RecordEvent`, `PostEvent` | `withdrawal.posted` or `overdraft.nsf_denied` | Dr 2110 / Cr 1110; NSF denial is no-GL plus possible fee | Event detail, receipt, journal trace | Available balance, holds, overdraft policy, teller session |
| Complete internal transfer | `Core::OperationalEvents`, `Accounts` | `AuthorizeDebit`, `RecordEvent`, `PostEvent` | `transfer.completed` or `overdraft.nsf_denied` | Dr 2110 source / Cr 2110 destination | Event detail, journal trace | Source/destination open, distinct accounts, available balance |
| Place hold | `Accounts` | `Accounts::Commands::PlaceHold` | `hold.placed` posted immediately | None | Holds list, account profile, statement metadata where applicable | Open account, positive amount, deposit-link constraints, idempotency |
| Release or expire hold | `Accounts` | `ReleaseHold`, `ExpireDueHolds` | `hold.released` in current shipped path | None | Holds history and account profile | Active hold, supervisor/capability for manual release, idempotency |
| Assess manual/service fee | `Core::OperationalEvents`, `Deposits` / `Accounts` | `RecordEvent`, `PostEvent`; fee engine commands where automated | `fee.assessed` | Dr 2110 / Cr 4510 | Event detail, statement line | Available balance unless forced NSF fee, product fee rule if automated |
| Waive fee | `Core::OperationalEvents`, `Branch` workflow | `RecordEvent`, `PostEvent` | `fee.waived` | Dr 4510 / Cr 2110 | Event detail, statement line | Prior posted fee, same account/amount, fee-waive capability |
| Reverse posted financial event | `Core::OperationalEvents`, `Core::Posting` | `RecordReversal`, `PostEvent` | `posting.reversal` | Mirrors original journal with compensating legs | Reversal linkage, journal trace | Original posted event, reversible event type, supervisor/capability, hold guards |
| Close teller session | `Teller` | `Teller::Commands::CloseSession` | Teller session status change; optional `teller.drawer.variance.posted` | Optional GL 1110 / 5190 for variance flag | Branch dashboard, variance views | Expected cash computed server-side; operator supplies actual count; variance threshold; supervisor approval if required |
| View trial balance | `Core::Ledger`, `Teller` query | Trial balance report query | None | Read-only | Trial balance response | Current/open business date rules |
| Check EOD readiness | `Teller`, `Core::BusinessDate` | `Teller::Queries::EodReadiness` | None | Read-only | EOD readiness response | Trial balance, pending events, open sessions |
| Close business date | `Core::BusinessDate` | `CloseBusinessDate` | Business date close audit | None by itself | Close event/history | EOD readiness satisfied, authorized actor, singleton open day |

---

## 5. Phase 2: Cash Custody and Branch Controls

These capabilities deepen branch operations from teller-session control to institutional custody control.

| Branch activity | Owner | Command/query surface | Operational event / audit record | Posting behavior | Read model / evidence | Controls |
| --- | --- | --- | --- | --- | --- | --- |
| Create branch vault location | `Cash` | `Cash::Commands::CreateLocation` | Cash location lifecycle audit | None | Cash location list | Active operating unit, location type, currency |
| Create teller drawer location | `Cash` | `CreateLocation` | Cash location lifecycle audit | None | Cash location list, teller session defaults | Responsible operator, operating unit, active state |
| Link teller session to drawer | `Teller`, `Cash` | `OpenSession` resolving a drawer Cash location | Session row references drawer | None | Branch dashboard | Open drawer, active cash location, one open session per drawer policy |
| Vault-to-drawer transfer | `Cash` | `Cash::Commands::TransferCash`, `Cash::Commands::ApproveCashMovement` | `cash.movement.completed` | No GL for internal custody transfer | Cash position, movement activity | Dual control where required, no self-approval, sufficient vault custody balance |
| Drawer-to-vault transfer | `Cash` | `TransferCash`, `ApproveCashMovement` | `cash.movement.completed` | No GL for internal custody transfer | Cash position, movement activity | Teller/session status, approval policy |
| Record drawer or vault count | `Cash` | `Cash::Commands::RecordCashCount` | `cash.count.recorded` | None by default | Count history, reconciliation summary | Actor, location, business date, count completeness |
| Record cash variance | `Cash`, `Core::Posting` | `Cash::Commands::ApproveCashVariance` | `cash.variance.posted` | Dr/Cr `1110` / `5190` depending shortage or overage | Variance queue, reconciliation summary | Approval threshold, no self-approval, immutable count history |
| Receive external cash shipment | `Cash`, `Core::Posting` | `Cash::Commands::ReceiveExternalCashShipment` | `cash.shipment.received` | Dr `1110` / Cr `1130` | Movement evidence, journal trace | Branch vault destination, `cash.shipment.receive`, idempotency |
| Reconcile cash location | `Cash` | `Cash::Commands::ReconcileCashLocation`, `Cash::Queries::ReconciliationSummary` | Reconciliation artifact | None | Reconciliation package | Movements, counts, GL comparison, reviewer evidence |

ADR-0031 is the governing target model for internal custody. ADR-0035 accepts the narrow external receipt path into a branch vault. This phase still does not introduce outbound Fed/correspondent shipments, full shipment lifecycle state, ATM cash, denomination tracking, or settlement matching.

---

## 6. Phase 3: Branch Servicing Depth

These capabilities make branch/platform servicing complete enough for daily account maintenance while preserving domain ownership.

| Branch activity | Owner | Command/query surface | Operational event / audit record | Posting behavior | Read model / evidence | Controls |
| --- | --- | --- | --- | --- | --- | --- |
| Search customers | `Party`, Branch workspace | Customer search query | None | None | Search results | Branch access capability |
| View customer 360 | `Party`, `Accounts`, `Deposits` | Customer/account profile queries | None | None | Customer 360, account profile | Role/capability, redaction rules |
| View account activity | `Accounts`, `Core::OperationalEvents`, `Deposits` | Account activity/history queries | None | Read-only | Activity list, statement line context | Internal vs customer-safe view shaping |
| Maintain authorized signer | `Accounts` | Add/end signer commands | Account-party maintenance audit row | None | Account-party timeline | Supervisor/capability, no owner semantics change |
| Freeze or restrict account | `Accounts` | `Accounts::Commands::RestrictAccount`, `Accounts::Commands::UnrestrictAccount` | `account.restricted`, `account.unrestricted` no-GL events plus `account_restrictions` | None | Account profile, restriction history, operational event search | `account.maintain`, reason, effective dates, debit/close/full-freeze guards |
| Close account | `Accounts` | `Accounts::Commands::CloseAccount` | `account_lifecycle_events` row plus `account.closed` no-GL event | None | Account lifecycle history, operational event search | Zero balance, no active holds, no pending events, no close-blocking restrictions, `account.maintain` |
| Maintain contact details | `Party` | `Party::Commands::UpdateContactPoint` | `party_contact_audits` row; typed `party_emails`, `party_phones`, `party_addresses` | None | Customer contact summary and audit history | `party.contact.update`, append/supersede history, no customer portal semantics |
| Review servicing exceptions | `Workflow`, `Reporting` | Approval/exception queue queries | Approval request/decision records once implemented | Usually none | Exception queue, decision history | Assignment, no self-approval, reason capture |

This phase should not create a separate `CustomerService` workspace unless a distinct contact-center operating model emerges. Current internal servicing remains under the Branch workspace.

---

## 7. Phase 4: Product Behavior Engine

These capabilities make deposit behavior reproducible and configurable.

| Capability | Owner | Command/query surface | Operational event / audit record | Posting behavior | Read model / evidence | Controls |
| --- | --- | --- | --- | --- | --- | --- |
| Product contract snapshot | `Products`, `Accounts` | Product resolver, `OpenAccount` | Account contract snapshot | None | Account/product profile | Snapshot schema/version, product effective date |
| Rules evaluation trace | `Deposits`, `Products` | `Deposits::RulesEngine` candidate | Rule trace linked to event/hold/approval | None directly | Support/audit trace | Deterministic inputs, product contract reference |
| Product-driven holds | `Products`, `Accounts`, `Deposits` | Rules engine + `PlaceHold` | `hold.placed` | None | Hold history | Funds availability policy, Reg CC deferral until ADR |
| Product-driven fees | `Products`, `Deposits` | Fee assessment commands | `fee.assessed` | Dr 2110 / Cr fee income | Fee event, statement line | Rule eligibility, idempotency, waiver policy |
| Product-driven overdraft | `Products`, `Accounts`, `Deposits` | Debit authorization | `overdraft.nsf_denied`, fee event where applicable | Denial no-GL; fee may post | Event trace, support keys | Product policy, available balance, forced fee guard |
| Interest accrual/posting | `Deposits`, `Products` | Interest commands/engine | `interest.accrued`, `interest.posted` | Existing interest posting rules | Statement line, accrual trace | System channel, payout linkage, rounding |
| Product GL mapping | `Products`, `Core::Posting` | Future GL mapping resolver | Depends on event | Posting rules change | Posting tests and GL trace | Dedicated posting/GL ADR required |

ADR-0030 is the target architecture. This phase should not turn the product engine into a posting engine.

---

## 8. Phase 5: Negotiable Instruments / Official Checks

These capabilities require a new ADR before implementation.

| Capability | Owner | Command/query surface | Operational event / audit record | Posting behavior | Read model / evidence | Controls |
| --- | --- | --- | --- | --- | --- | --- |
| Account-funded official check issuance | TBD, likely `Instruments` | Future issue official check command | `official_check.issued` candidate | Likely Dr 2110 / Cr 2160 | Instrument record, receipt, event trace | Unique instrument number, funding validation, idempotency |
| Cash-funded official check issuance | `Instruments`, `Cash`, `Teller` | Future command | `official_check.issued` plus cash movement candidate | Cr 2160; cash custody movement required | Instrument record, cash activity | Open session/drawer, cash location controls |
| Official check void | `Instruments`, `Core::OperationalEvents` | Future void command | `official_check.voided` candidate | Reverses/relieves 2160 depending status | Instrument lifecycle | Not paid/settled, authorized actor |
| On-us check cashing | `Instruments` or future check domain | Future check cash command | `check.cashed.on_us` candidate | Likely Dr 2110 / Cr 1110 | Check record, receipt | Account validity, funds, presenter identity |
| Transit check cashing | TBD | Future command | Candidate check/cash event family | Likely uses collection/clearing accounts | Check record, return trace | Clearing/return risk; post-MVP |

The ADR must decide instrument table ownership, lifecycle states, posting events, void/replacement semantics, and reconciliation responsibilities.

---

## 9. Phase 6: External Payments, Rails, and Exceptions

These capabilities connect branch and account activity to external networks.

| Capability | Owner | Command/query surface | Operational event / audit record | Posting behavior | Read model / evidence | Controls |
| --- | --- | --- | --- | --- | --- | --- |
| ACH receipt ingestion | `Integration::Ach` | `IngestReceiptFile` | `ach.credit.received` | Dr 1120 / Cr 2110 | Ops ingestion result, event search | Structured input, deterministic idempotency, exact account lookup |
| ACH origination | `Integration` | Future origination command | Candidate ACH debit/credit origination events | Settlement and account postings TBD | Origination batch lifecycle | External API/customer authority, cutoff policy, ADR required |
| Wire transfer | `Integration` | Future wire command | Candidate wire event family | GL/account effects TBD | Wire lifecycle and audit | OFAC/sanctions, dual control, ADR required |
| Card/ATM settlement | `Integration` | Future settlement ingestion | Candidate card/ATM settlement events | Settlement and account postings TBD | Settlement reconciliation | Network files, authorization holds, ADR required |
| Returned item / exception | `Integration`, `Accounts`, `Workflow` | Future exception commands | Candidate return/exception events | Depends on item type | Exception queue, support trace | Timeliness, reversal/chargeback semantics |

Inbound ingestion and outbound origination should be planned separately. Existing ACH receipt ingestion does not imply ACH origination, wires, cards, or full file lifecycle support.

---

## 10. Phase 7: Compliance, Reporting, and Scale

These capabilities support oversight and production-scale operations.

| Capability | Owner | Command/query surface | Operational event / audit record | Posting behavior | Read model / evidence | Controls |
| --- | --- | --- | --- | --- | --- | --- |
| AML alert review | `Compliance` | Future case/review commands | Alert/case evidence | None directly | Case queue | Alert source, reviewer, disposition |
| CTR support | `Compliance`, `Reporting`, `Cash` | Future CTR aggregation/reporting | CTR evidence record | None directly | CTR report package | Cash event aggregation, threshold rules |
| Sanctions screening | `Compliance`, `Integration` | Future screening adapter | Screening result reference | None | Screening evidence | Match disposition, audit trail |
| Operational dashboards | `Reporting` | Projection refresh/query | None or projection audit | Read-only | Branch dashboards | Rebuildable projections |
| Daily balance snapshots | `Reporting` | Snapshot materializer | Snapshot audit | Read-only | Balance reports | Reconciliation to journal truth |
| Branch-aware event filters | `Core::OperationalEvents`, `Reporting` | Event search filters | None | Read-only | Support search | Uses `operating_unit_id`; no branch GL implication |
| Multi-entity accounting | `Core::Ledger` plus future entity model | Future commands/queries | TBD | Major GL change | Consolidation reports | ADR required before design |

---

## 11. ADR Gaps by Phase

| Phase | ADR gap |
| --- | --- |
| Phase 2 Cash | ADR-0031 and ADR-0035 cover the shipped foundation; future ADRs are still needed for EOD cash blocking, full shipment lifecycle, denomination tracking, ATM cash, or branch GL |
| Phase 3 Servicing | ADR-0036 covers restrictions, close lifecycle, Party contact audit, command guards, Workflow deferral, and composed timelines |
| Phase 4 Product behavior | ADR-0030 follow-up when snapshots, rules engine traces, product GL mapping, or Reg CC are implemented |
| Phase 5 Instruments | New ADR for official checks/check cashing ownership, lifecycle, events, posting, and reconciliation |
| Phase 6 External rails | New or updated ADR per rail and direction: inbound ingestion vs outbound origination |
| Phase 7 Compliance/scale | ADRs for CTR, AML cases, daily snapshots, branch business dates, branch GL, or multi-entity accounting |

---

## 12. References

- [BankCORE branch operations roadmap](../roadmap-branch-operations.md)
- [BankCORE module catalog](bankcore-module-catalog.md)
- [MVP vs Full System](../concepts/01-mvp-vs-core.md)
- [Development roadmap](../roadmap.md)
- [Deferred roadmap completion guide](../roadmap-deferred-completion.md)
- [ADR-0012: Posting rule registry and journal subledger](../adr/0012-posting-rule-registry-and-journal-subledger.md)
- [ADR-0013: Holds, available balance, and servicing operational events](../adr/0013-holds-available-and-servicing-events.md)
- [ADR-0014: Teller sessions and control events](../adr/0014-teller-sessions-and-control-events.md)
- [ADR-0016: Trial balance and EOD readiness](../adr/0016-trial-balance-and-eod-readiness.md)
- [ADR-0018: Business date close and posting invariant](../adr/0018-business-date-close-and-posting-invariant.md)
- [ADR-0026: Branch CSR servicing](../adr/0026-branch-csr-servicing.md)
- [ADR-0028: ACH receipt ingestion](../adr/0028-ach-receipt-ingestion.md)
- [ADR-0030: Deposit account product engine](../adr/0030-deposit-account-product-engine.md)
- [ADR-0031: Cash inventory and management](../adr/0031-cash-inventory-and-management.md)
- [ADR-0032: Operating units and branch scope](../adr/0032-operating-units-and-branch-scope.md)
- [ADR-0036: Branch servicing event and audit taxonomy](../adr/0036-branch-servicing-event-audit-taxonomy.md)
- [ADR-0037: Internal staff authorized surfaces](../adr/0037-internal-staff-authorized-surfaces.md)
