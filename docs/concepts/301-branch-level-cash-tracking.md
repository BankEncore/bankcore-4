# Branch-Level Cash Tracking in BankCORE

## Purpose

A bank branch needs to track cash at multiple levels because “cash” means more than one thing operationally.

At the branch level, BankCORE must distinguish between:

1. **Accounting cash**

   * The institution’s official financial position.
   * Reflected in the general ledger.
   * Example: total cash owned by the institution at a branch.

2. **Physical cash custody**

   * Where currency and coin physically reside.
   * Example: vault, teller drawer, ATM cassette, night drop, shipment bag, internal transit.

3. **Teller session cash**

   * The cash a teller is expected to have based on the day’s teller activity.
   * Example: opening drawer amount plus cash received minus cash paid out.

4. **Counted cash**

   * The actual cash physically counted at a point in time.
   * Example: drawer close count, vault count, surprise audit, shipment verification.

These layers overlap, but they should not be treated as the same record. A teller withdrawal may reduce the teller’s expected drawer balance and the customer’s deposit account balance immediately, but the physical custody system still needs to know which drawer supplied the bills. Likewise, a vault-to-drawer transfer changes physical custody but should not create customer activity or income/expense by itself.

## Alignment with BankCORE implementation and roadmap

**Module mapping (see [module catalog](../architecture/bankcore-module-catalog.md)):** `Cash` owns custody locations, movements, balances, counts, and custody variances; `Teller` owns teller sessions and drawer/session variance workflow; `Core::OperationalEvents` and `Core::Posting` own customer-facing monetary intent and GL posting; `Workspace` / `Organization` own operators, capabilities, and operating-unit scope. **MVP vs broader scope** follows [01-mvp-vs-core.md](01-mvp-vs-core.md): branch-safe cash control is MVP-aligned; denomination tracking, full shipment lifecycles, and every instrument type in this document are phased. **Staff authorized surfaces** (teller line, teller supervisor, CSR, and JSON `/teller`) are defined in [ADR-0037](../adr/0037-internal-staff-authorized-surfaces.md).

This concept doc is the **target** operating model for branch cash. **Shipped and planned engineering** already align on the same separation of concerns: general ledger truth is not the custody subledger; internal vault/drawer moves stay off GL except where ADRs define variance or external settlement posting.

**Strong alignment today**

- Four-layer distinction (accounting vs physical custody vs teller expected vs counted) matches [ADR-0031](../adr/0031-cash-inventory-and-management.md) and [roadmap branch operations Phase 2](../roadmap-branch-operations.md#6-phase-2-cash-custody-and-branch-controls).
- Location-based custody: `cash_locations` (`branch_vault`, `teller_drawer`, `internal_transit`), movements, rebuildable balances, counts, dual-step approvals where policy requires.
- Teller sessions resolve a **teller drawer** `Cash` location; teller **expected** cash is derived from posted teller-channel cash events on the session (`deposit.accepted`, `withdrawal.posted`).
- Session close and variance: threshold, supervisor approval, optional drawer variance GL per [ADR-0020](../adr/0020-teller-drawer-variance-gl-posting.md).
- Inbound external cash receipt into a branch vault: [ADR-0035](../adr/0035-external-cash-shipments.md).
- Capability gates and maker/checker-style rules on custody operations ([ADR-0029](../adr/0029-capability-first-authorization-layer.md)); business-date attribution per core business-date rules.

**Partial alignment (same direction, less depth than this document)**

- **Movement lifecycle:** internal transfers use approval/completion states; full “requested → sealed → in transit → received” shipment modeling is not product-complete except for the narrow inbound receipt slice.
- **Teller drawer detail:** expected cash is **event-derived**; explicit opening-float fields, per-instrument drawer effects (e.g. check deposit vs cash), and mixed-deposit tickets are product extensions beyond the first custody slice.
- **Reconciliation and EOD:** position and reconciliation queries exist; wiring **all** custody exceptions into EOD readiness as first-class warnings remains roadmap hardening.
- **Roles:** capability codes map teller vs supervisor vs ops; seed role bundles may not match every responsibility row in [Branch roles and responsibilities](#branch-roles-and-responsibilities) without configuration.

**Forward-looking relative to this document**

- Additional **location types** (ATM, recycler, night drop, shipment bag, `external_transit`, cash suspense): described in ADR-0031 as growth; not fully implemented as operating flows.
- **Denomination-level** movements and counts: strongly preferable here; current modeling emphasizes **aggregate** USD at location/movement level until a dedicated slice lands.
- **Outbound** external shipments, **inter-branch** custody lifecycle, **vault/drawer limit** policies, and **GL ↔ custody** certification reports: require follow-up ADRs and phased delivery—not contradictions of this concept, but **not** fully implemented yet.

---

# Core Principle

## Branch cash should be tracked as a location-based custody system

At the branch level, BankCORE should model cash as being held in specific **cash locations**. Each cash location belongs to an operating unit, usually a branch.

Examples:

| Cash Location Type | Description                                                                        |
| ------------------ | ---------------------------------------------------------------------------------- |
| Branch vault       | Main cash vault for the branch                                                     |
| Teller drawer      | Cash assigned to a teller workstation/session                                      |
| ATM cassette       | Cash loaded into branch ATM equipment                                              |
| Recycler           | Cash held in teller cash recycler hardware                                         |
| Night depository   | Cash/check custody before processing                                               |
| Shipment bag       | Cash prepared for pickup or received from carrier                                  |
| Internal transit   | Cash moving between branches or operating units                                    |
| External transit   | Cash moving to/from Fed, correspondent bank, armored carrier, or cash vault vendor |
| Cash suspense      | Temporary holding location for unresolved or exception items                       |

This lets BankCORE answer a critical operational question:

> Where is the institution’s cash physically supposed to be right now?

---

# Branch-Level Cash Model

## 1. Branch vault

The **branch vault** is the primary cash custody location for a branch.

It should track:

| Data Point                   | Purpose                                      |
| ---------------------------- | -------------------------------------------- |
| Branch / operating unit      | Which branch owns the vault                  |
| Vault location code          | Stable identifier for the vault              |
| Current book/custody balance | Expected cash held in vault                  |
| Last verified count          | Most recent confirmed physical count         |
| Count variance               | Difference between expected and actual count |
| Authorized custodians        | Staff allowed to access/control the vault    |
| Dual-control status          | Whether two-person control is required       |
| Cash limits                  | Minimum/maximum vault cash thresholds        |
| Shipment status              | Pending inbound/outbound shipments           |
| Audit history                | Counts, transfers, adjustments, approvals    |

The vault is not just a GL account. It is a controlled physical location. The GL may say the branch has $200,000 in cash, but operations still need to know whether that cash is in the vault, teller drawers, ATM, transit, or suspense.

---

## 2. Teller drawers

A **teller drawer** represents cash assigned to a teller or teller workstation.

A teller drawer should track:

| Data Point               | Purpose                                           |
| ------------------------ | ------------------------------------------------- |
| Branch / operating unit  | Which branch the drawer belongs to                |
| Assigned teller/operator | Who is responsible for the drawer                 |
| Teller session           | Which open session controls the drawer            |
| Opening cash             | Starting cash issued to the teller                |
| Cash in                  | Cash received during the session                  |
| Cash out                 | Cash paid out during the session                  |
| Expected cash            | System-calculated drawer amount                   |
| Actual cash count        | Teller’s close count                              |
| Variance                 | Over/short amount                                 |
| Drawer status            | Available, assigned, open, closed, suspended      |
| Approval state           | Whether variance/close requires supervisor review |

The teller drawer is where BankCORE’s teller operations and cash custody systems meet.

A teller transaction affects:

| Transaction                   | Customer/Subledger Effect                        | Drawer Effect                                   |
| ----------------------------- | ------------------------------------------------ | ----------------------------------------------- |
| Cash deposit                  | Increases customer account balance               | Increases teller drawer cash                    |
| Cash withdrawal               | Decreases customer account balance               | Decreases teller drawer cash                    |
| Check deposit                 | Increases account balance or memo/hold amount    | Does not increase cash; creates item custody    |
| Check cashing                 | No deposit account effect, or fee/account effect | Decreases drawer cash; may increase check items |
| Bank draft purchase with cash | Issues official check liability                  | Increases drawer cash                           |
| Fee paid in cash              | Increases income/fee GL                          | Increases drawer cash                           |

This means drawer cash should be reconciled against teller session activity, not merely stored as a static balance.

---

## 3. ATM and cash recycler locations

Branches may have cash outside the vault and teller drawers.

BankCORE may eventually need to support:

| Location             | Tracking Need                              |
| -------------------- | ------------------------------------------ |
| ATM cassette         | Cash loaded, dispensed, returned, balanced |
| Teller cash recycler | Cash accepted/dispensed automatically      |
| Coin vault/machine   | Coin inventory and settlement              |
| Cash dispenser       | Cash loaded and dispensed by device        |
| Night drop           | Custody before branch processing           |

These locations should be treated as cash custody locations because the institution still owns or controls the cash while it is physically outside the main vault.

ATM and recycler activity may also involve device settlement, exception handling, and reconciliation to switch/network reports. That can be deferred, but the cash-location model should not prevent it.

---

# Cash Movement Types

Cash tracking at the branch level requires a formal movement model.

## Internal branch movements

These move cash within the same branch.

Examples:

| Movement               | Description                                | GL Impact                             |
| ---------------------- | ------------------------------------------ | ------------------------------------- |
| Vault to teller drawer | Teller buys cash from vault/opening drawer | Usually none                          |
| Teller drawer to vault | Teller sells excess cash back to vault     | Usually none                          |
| Drawer to drawer       | One teller transfers cash to another       | Usually none                          |
| Vault to ATM           | Cash loaded into ATM                       | Usually none or device subledger only |
| ATM to vault           | Cash removed from ATM                      | Usually none                          |
| Vault to recycler      | Cash loaded to recycler                    | Usually none                          |
| Recycler to vault      | Recycler emptied to vault                  | Usually none                          |

These are **custody movements**, not customer transactions. They should be auditable, but they usually should not create GL entries unless the movement reveals a variance or adjustment.

---

## Inter-branch movements

Cash may move between branches.

Examples:

| Movement                             | Description                                                  |
| ------------------------------------ | ------------------------------------------------------------ |
| Branch A vault to Branch B vault     | Cash shipped between branches                                |
| Branch vault to operations center    | Excess cash sent to central cash operations                  |
| Operations center to branch vault    | Cash supplied to branch                                      |
| Branch to branch via armored carrier | Cash physically leaves one branch before arriving at another |

Inter-branch movements introduce timing and custody complexity.

BankCORE should support a lifecycle such as:

1. **Movement requested**
2. **Shipment prepared**
3. **Cash counted and sealed**
4. **Shipment released**
5. **Cash in transit**
6. **Shipment received**
7. **Receiving branch count performed**
8. **Movement completed**
9. **Variance resolved, if any**

During transit, cash should not disappear from the institution’s records. It should move from:

> Branch A vault → internal transit → Branch B vault

This permits the institution to know:

* Which branch released the cash
* Which branch expects to receive it
* Who prepared the shipment
* Who approved it
* Who transported it
* Whether the receiving count matched the sending count
* Whether a variance exists

---

## External cash shipments

Branches may order or return cash through:

* Federal Reserve Bank
* Correspondent bank
* Bankers’ bank
* Armored carrier
* Cash vault vendor
* Central cash operations department

BankCORE should support inbound and outbound external shipments.

### Inbound shipment example

> Fed/correspondent/cash vendor → external transit → branch vault

Tracked data should include:

| Data Point               | Purpose                                       |
| ------------------------ | --------------------------------------------- |
| Shipment source          | Fed, correspondent, vault vendor, central ops |
| Expected amount          | Amount ordered or advised                     |
| Denomination breakdown   | Bills/coin expected                           |
| Carrier/reference number | Audit and reconciliation                      |
| Prepared/received by     | Custody responsibility                        |
| Received count           | Actual branch count                           |
| Variance                 | Difference from expected                      |
| Approval                 | Supervisor/dual-control confirmation          |

### Outbound shipment example

> Branch vault → external transit → Fed/correspondent/cash vendor

Tracked data should include:

| Data Point                  | Purpose                                 |
| --------------------------- | --------------------------------------- |
| Destination                 | Fed, correspondent, vendor, central ops |
| Shipment amount             | Total cash released                     |
| Denomination breakdown      | Bills/coin shipped                      |
| Bag/seal numbers            | Physical control                        |
| Released by                 | Branch staff custody                    |
| Approved by                 | Supervisor/dual control                 |
| Carrier pickup confirmation | Chain of custody                        |
| Settlement/confirmation     | Confirmation from receiving party       |

---

# Denomination Tracking

Branch cash can be tracked at two levels:

1. **Total-value tracking**

   * Example: vault has $125,000.
   * Easier to implement.
   * Sufficient for high-level accounting.

2. **Denomination-level tracking**

   * Example: vault has:

     * 400 × $100
     * 600 × $50
     * 1,000 × $20
     * 500 × $10
     * 300 × $5
     * 200 × $1
   * Needed for vault management, teller buys/sells, shipment prep, and audit.

For a banking system, denomination tracking is strongly preferable for vaults, teller drawers, ATM loads, and cash shipments.

## Recommended denomination model

Each count or movement should be able to capture:

| Field          | Description                                                             |
| -------------- | ----------------------------------------------------------------------- |
| Denomination   | $100, $50, $20, $10, $5, $2, $1, coins                                  |
| Quantity       | Number of bills/coins/rolls                                             |
| Amount         | Quantity × denomination                                                 |
| Currency       | Usually USD, but should be explicit if multi-currency support may exist |
| Condition/type | Fit, unfit, mutilated, coin, strap, bundle, loose                       |

Denomination detail allows BankCORE to support:

* Teller drawer opening counts
* Teller drawer close counts
* Vault counts
* Vault buys/sells
* Cash ordering
* Shipment preparation
* ATM/recycler loading
* Cash-limit monitoring
* Surprise audits
* Investigation of variances

---

# Counts and Reconciliation

Cash tracking requires periodic counts.

## Count types

| Count Type           | Description                                  |
| -------------------- | -------------------------------------------- |
| Opening teller count | Teller confirms starting drawer cash         |
| Closing teller count | Teller counts drawer at session close        |
| Vault count          | Branch verifies vault cash                   |
| Surprise count       | Unscheduled audit count                      |
| Shipment count       | Cash counted before release or after receipt |
| ATM/recycler count   | Device cash counted during servicing         |
| Variance recount     | Follow-up count after discrepancy            |

Each count should preserve:

| Data Point          | Purpose                          |
| ------------------- | -------------------------------- |
| Location counted    | Vault, drawer, ATM, etc.         |
| Counted by          | Staff member performing count    |
| Witnessed by        | Second staff member, if required |
| Count time          | Timestamp                        |
| Business date       | Accounting/operations date       |
| Expected amount     | System balance before count      |
| Actual amount       | Counted amount                   |
| Variance            | Actual minus expected            |
| Denomination detail | Count composition                |
| Notes/reason        | Explanation for variance         |
| Approval status     | Supervisor approval if needed    |

---

# Variance Handling

A cash variance occurs when actual counted cash does not match expected cash.

Examples:

| Scenario                                           | Variance   |
| -------------------------------------------------- | ---------- |
| Teller expected $10,000 but counted $9,980         | $20 short  |
| Vault expected $150,000 but counted $150,100       | $100 over  |
| Shipment expected $25,000 but received $24,900     | $100 short |
| ATM expected $40,000 remaining but counted $39,960 | $40 short  |

Variance handling should be controlled and auditable.

## Recommended variance lifecycle

1. **Variance detected**
2. **Recount required**
3. **Supervisor review**
4. **Explanation captured**
5. **Variance approved or rejected**
6. **Operational event recorded**
7. **GL entry posted if financial adjustment is required**
8. **Location balance corrected**
9. **Audit trail preserved**

A variance is one of the places where physical custody and accounting may need to reconnect. A simple drawer-to-vault transfer may not affect GL, but a confirmed over/short generally should.

Example:

| Variance            | Possible GL Treatment                                    |
| ------------------- | -------------------------------------------------------- |
| Teller drawer short | Debit teller over/short expense or suspense; credit cash |
| Teller drawer over  | Debit cash; credit teller over/short income or suspense  |
| Vault short         | Debit cash over/short or suspense; credit cash           |
| Vault over          | Debit cash; credit cash over/short or suspense           |

BankCORE should avoid silently adjusting balances without an auditable variance event.

---

# Branch Cash Limits

Branches typically need cash limits and monitoring.

## Limit types

| Limit                  | Purpose                                                    |
| ---------------------- | ---------------------------------------------------------- |
| Vault minimum          | Ensures branch can meet expected demand                    |
| Vault maximum          | Reduces risk/excess cash exposure                          |
| Teller drawer limit    | Prevents tellers from holding excess cash                  |
| ATM load limit         | Controls device cash exposure                              |
| Shipment threshold     | Triggers order/return recommendation                       |
| Insurance limit        | Ensures cash held does not exceed coverage                 |
| Dual-control threshold | Requires second person above certain amount                |
| Approval threshold     | Requires supervisor approval for movements/count variances |

BankCORE should be able to flag:

* Vault below minimum
* Vault above maximum
* Teller drawer above limit
* Shipment needed
* Large cash transfer requiring approval
* Large cash withdrawal requiring supervisor override
* Unresolved variance
* Cash location not counted within required interval

---

# Branch Roles and Responsibilities

Cash tracking is also a control system. The software should distinguish who can initiate, approve, receive, count, and adjust cash.

## Teller

A teller may need to:

* Open drawer/session
* Confirm opening cash
* Accept cash deposits
* Pay cash withdrawals
* Request cash from vault
* Return excess cash to vault
* Transfer cash to another teller, if permitted
* Close drawer/session
* Enter closing count
* Explain variance
* View own drawer position

## Head teller / supervisor

A supervisor may need to:

* Approve drawer opening exceptions
* Approve vault-to-drawer transfers
* Approve drawer-to-vault returns
* Approve teller variances
* View all branch drawer positions
* Perform or witness vault counts
* Approve cash shipments
* Override limits
* Review unresolved cash exceptions

## Branch manager

A branch manager may need to:

* View branch cash position
* Monitor cash limits
* Review teller performance and variances
* Approve large movements or shipments
* Review daily branch cash reconciliation
* Certify branch cash position at close

## Operations / cash management

Central operations may need to:

* Monitor cash across branches
* Initiate inter-branch transfers
* Manage Fed/correspondent orders
* Manage armored carrier shipments
* Review branch cash limits
* Investigate unresolved variances
* Reconcile GL cash to custody cash

---

# Daily Branch Cash Cycle

A branch-level cash model should support the full daily cycle.

## Start of day

Typical activities:

1. Branch opens business date.
2. Vault cash position is reviewed.
3. Teller drawers are assigned.
4. Tellers receive opening cash.
5. Tellers confirm opening drawer counts.
6. Exceptions are escalated before customer transactions begin.

## During the day

Typical activities:

1. Customers make deposits and withdrawals.
2. Teller drawer expected balances change.
3. Tellers buy/sell cash from vault.
4. Supervisors approve large movements.
5. Branch monitors drawer/vault limits.
6. ATM/recycler servicing may occur.
7. Shipments may be received or prepared.
8. Cash exceptions are logged.

## End of day

Typical activities:

1. Tellers close sessions.
2. Teller drawers are counted.
3. Variances are reviewed.
4. Excess cash is returned to vault.
5. Vault is counted or verified.
6. Shipments are reconciled.
7. Branch cash position is certified.
8. EOD checks confirm no unresolved cash exceptions.

---

# Reconciliation Targets

Branch cash needs several reconciliation views.

## Teller session reconciliation

Answers:

> Did the teller’s actual drawer cash match the expected cash from teller activity?

Compares:

* Opening cash
* Cash deposits
* Cash withdrawals
* Cash purchases/returns from vault
* Cash fees collected
* Cash paid out
* Expected drawer balance
* Actual drawer count

---

## Cash custody reconciliation

Answers:

> Does the sum of all branch cash locations equal the branch’s expected physical cash?

Compares:

* Vault balance
* Teller drawer balances
* ATM/recycler balances
* Cash in transit
* Cash suspense
* Shipment locations
* Counted balances
* Open movements

---

## GL reconciliation

Answers:

> Does the branch’s cash custody total reconcile to the general ledger?

Compares:

* GL cash accounts by branch/cost center
* Cash location balances
* Posted cash movements that affect GL
* Variance postings
* Shipments in transit
* Suspense accounts

---

# Accounting Treatment

Not every cash movement should affect GL.

## Movements with no ordinary GL impact

Usually no GL entry is needed for:

* Vault to teller drawer
* Teller drawer to vault
* Teller drawer to teller drawer
* Vault to ATM
* ATM to vault
* Vault to recycler
* Recycler to vault

These are custody reclassifications within the same institution.

However, BankCORE may still track them in a cash subledger or cash custody ledger.

## Movements that may affect GL

GL impact may be required for:

* Customer cash deposit
* Customer cash withdrawal
* Fee paid in cash
* Bank draft sold for cash
* Confirmed cash over/short
* External cash shipment settlement
* Loss/theft/write-off
* Cash adjustment
* Currency mutilation/write-down
* Cross-entity transfer if operating entities differ

The key rule:

> Custody movement changes where cash is. Financial posting changes what the institution owns, owes, earned, lost, or must recognize.

---

# Recommended BankCORE Concepts

## Cash locations

BankCORE should have durable cash locations such as:

```text
branch_vault
teller_drawer
atm
recycler
night_drop
shipment
internal_transit
external_transit
cash_suspense
```

Each location should belong to:

* Institution
* Operating unit / branch
* Optional workstation
* Optional assigned operator
* Optional parent location
* Status

---

## Cash movements

Cash movements should record custody transfers.

Minimum fields:

| Field                | Description                                                   |
| -------------------- | ------------------------------------------------------------- |
| Source location      | Where cash leaves                                             |
| Destination location | Where cash goes                                               |
| Amount               | Total value                                                   |
| Denomination detail  | Optional but recommended                                      |
| Business date        | Operational date                                              |
| Initiated by         | Actor creating movement                                       |
| Approved by          | Actor approving, if required                                  |
| Released by          | Actor releasing cash                                          |
| Received by          | Actor receiving cash                                          |
| Status               | Pending, approved, released, received, completed, canceled    |
| Reason code          | Drawer buy, drawer sell, shipment, ATM load, audit adjustment |
| Reference            | Shipment number, seal number, ticket, note                    |
| Audit trail          | Immutable event history                                       |

---

## Cash counts

Cash counts should be separate from movements.

A count proves or challenges the expected balance of a location. It does not necessarily move cash.

Minimum fields:

| Field               | Description                                  |
| ------------------- | -------------------------------------------- |
| Cash location       | Location counted                             |
| Expected amount     | System balance                               |
| Actual amount       | Counted balance                              |
| Variance amount     | Actual minus expected                        |
| Denomination detail | Count composition                            |
| Counted by          | Actor                                        |
| Witnessed by        | Actor, if required                           |
| Business date       | Branch business date                         |
| Count reason        | Open, close, vault audit, shipment, surprise |
| Status              | Draft, submitted, approved, posted           |
| Notes               | Explanation                                  |

---

## Cash variances

Cash variances should be explicit records, not hidden balance edits.

Minimum fields:

| Field             | Description                                 |
| ----------------- | ------------------------------------------- |
| Related count     | Count that found the variance               |
| Location          | Vault, drawer, ATM, shipment                |
| Amount            | Over/short                                  |
| Responsible actor | Teller/custodian if applicable              |
| Explanation       | Required reason                             |
| Approval status   | Supervisor review                           |
| Posting status    | Whether GL adjustment posted                |
| Resolution        | Accepted, corrected, reversed, investigated |
| Audit trail       | Full event history                          |

---

# What Branch Staff Need to See

## Teller view

A teller should see:

* Current drawer/session status
* Opening cash
* Cash received
* Cash paid out
* Expected drawer cash
* Pending vault buys/sells
* Required approvals
* Closing count entry
* Variance status

The teller does not need full branch vault analytics unless permitted.

---

## Supervisor view

A supervisor should see:

* All open teller drawers
* Drawer expected balances
* Drawer limits
* Pending cash movements
* Pending approvals
* Open variances
* Vault balance
* Recent vault activity
* Shipment status
* End-of-day cash readiness

---

## Branch manager view

A branch manager should see:

* Total branch cash
* Vault cash
* Teller drawer totals
* ATM/recycler totals
* Cash in transit
* Open exceptions
* Limit alerts
* Daily reconciliation status
* Trends in over/short activity
* Shipment needs

---

## Operations/cash management view

Central operations should see:

* Cash by branch
* Cash by location type
* Cash above/below limits
* Pending shipments
* Inter-branch cash in transit
* External cash orders/returns
* Large variances
* Aging unresolved exceptions
* GL-to-custody reconciliation

---

# Key Control Requirements

Branch-level cash tracking should enforce:

1. **Segregation of duties**

   * The person initiating a large movement should not always be able to approve it.

2. **Dual control**

   * Vault access, shipment preparation, and large counts may require two actors.

3. **Immutable audit trail**

   * Movements, counts, approvals, reversals, and adjustments must be preserved.

4. **No silent balance edits**

   * Corrections should be new events, not updates to prior records.

5. **Business-date awareness**

   * Cash activity must attach to the controlled branch business date.

6. **Location-level accountability**

   * Every dollar should be assigned to a known cash location or transit/suspense state.

7. **Variance workflow**

   * Differences between expected and actual cash require review, explanation, and resolution.

8. **Approval thresholds**

   * Large movements, large variances, and limit overrides should require supervisor approval.

9. **EOD readiness checks**

   * Branch close should detect unresolved sessions, pending movements, unapproved variances, and open shipments.

---

# Suggested Summary for BankCORE

BankCORE should track branch cash as a controlled custody system layered alongside, but distinct from, the accounting ledger and teller transaction system. Customer transactions determine account and GL effects; teller sessions determine expected drawer cash; cash locations determine where physical currency and coin are held; counts verify actual cash; and variances reconcile differences through controlled approval and posting workflows.

At the branch level, cash should be tracked across vaults, teller drawers, ATMs, recyclers, shipments, transit, and suspense locations. Most internal cash movements, such as vault-to-drawer or drawer-to-vault transfers, are custody movements rather than GL events. GL postings become necessary when customer transactions occur, fees are collected, external settlement occurs, or confirmed over/short variances require financial recognition.

The result is a model that can answer four essential questions:

1. **How much cash does the branch have?**
2. **Where is that cash physically located?**
3. **Who is responsible for it right now?**
4. **Does counted cash agree with expected cash and GL cash?**
