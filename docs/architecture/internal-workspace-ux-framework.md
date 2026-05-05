# Internal Workspace UX Framework

**Status:** Draft  
**Scope:** Internal Rails-rendered `branch`, `ops`, and `admin` workspaces  
**Aligns with:** [ADR-0025](../adr/0025-internal-workspace-ui.md), [ADR-0037](../adr/0037-internal-staff-authorized-surfaces.md), [ADR-0042](../adr/0042-business-date-monitoring-and-drilldown-surfaces.md), [branch-operations-capability-map.md](branch-operations-capability-map.md)

---

## 1. Purpose

BankCORE's internal UI has grown screen by screen around valid domain commands and queries, but the interaction model is still inconsistent.

Current operator friction is not mainly about missing data. It is about:

- too many equal-weight boxes
- weak visual hierarchy
- alerts that move content after actions
- forms that read like field bags instead of workflows
- buttons and links that do not communicate action state clearly

This document defines a shared UX framework for internal workspaces so Branch and Ops screens feel like one operating system rather than a collection of unrelated pages.

This is not a customer-facing design system. It is an internal operator framework optimized for:

- scanability
- operational confidence
- low-friction repetitive work
- explainability and control

---

## 2. Core Rules

### 2.1 Domain truth still wins

This framework does not move domain ownership into the UI.

- Branch and Ops remain authorized surfaces over existing commands and queries.
- Screens should clarify truth, not invent new truth.
- UX polish must not hide business-date, posting, teller-session, or cash-custody boundaries.

### 2.2 Fewer visual primitives

The interface should use fewer surface types with clearer jobs.

If every section is a bordered white card with the same weight, nothing is legible at speed.

### 2.3 Stable page chrome

Success and error feedback must not push the user's working area around unexpectedly.

Layout stability is an operational correctness issue, not cosmetic polish.

### 2.4 Task-first internal UX

Internal users usually arrive with intent:

- find a customer
- perform a teller transaction
- resolve an approval
- review today's state
- explain a record

Navigation and page structure should serve that intent directly.

### 2.5 State-aware, audit-explainable UX

BankCORE internal UX is not just task-first. It must also be:

- state-aware
- audit-explainable
- operationally legible

That means screens should not only help the operator do something. They should also make it clear:

- what operational state the operator is in
- what financial or custody state will be affected
- how to explain the result after the fact

This is especially important for:

- business-date-sensitive screens
- teller-session-sensitive screens
- approval-sensitive screens
- financial record detail screens

---

## 3. Page Types

Every internal page should declare one primary page type.

### 3.1 Hub page

Purpose:

- orient the operator
- surface the most important current state
- route to next actions

Examples:

- Branch dashboard
- Ops workspace
- Close package

Rules:

- keep summary density low
- emphasize status and next steps
- avoid long detailed lists unless the page's main job is queue review

### 3.2 Queue or index page

Purpose:

- review many rows
- filter
- triage
- drill into detail

Examples:

- Ops operational event search
- Branch operational events
- future Ops teller sessions

Rules:

- context and filters first
- results second
- avoid decorative cards where a table or list is clearer
- active filters must be visible in copy, not only in form fields

### 3.3 Record detail page

Purpose:

- explain one record clearly
- support audit and operational follow-up

Examples:

- Ops operational event detail
- Branch account profile
- future Ops teller session detail

Rules:

- key facts up top
- actions grouped near the header
- supporting sections below in descending importance

### 3.4 Transaction form page

Purpose:

- safely complete one operation

Examples:

- deposit
- withdrawal
- hold placement
- reversal
- fee waiver

Rules:

- show task context before fields
- group fields by decision step
- isolate warnings and validation clearly
- make submit state obvious

---

## 4. Layout Primitives

Use these primitives consistently.

### 4.1 Page header

Contains:

- page title
- one-sentence purpose
- top-level actions only

Should not contain:

- dense metrics
- secondary explanation better placed below

### 4.1a Operational context strip

For pages where operational state matters, the page header should be followed by a stable context strip.

This strip is not a decorative badge row. It is a compact statement of the operational frame the user is working inside.

Depending on the page, it may include:

- current or reviewed business date
- operating unit
- actor or authorized surface
- teller session
- cash location
- approval state
- posting or record state

This context should be:

- visible without scrolling deep into the page
- stable across the task
- non-dismissible

Not every page needs every field, but business-date, session, approval, and cash-sensitive screens should not hide their operating context.

### 4.2 Status banner

Use for:

- current business date context
- blocker/warning summaries
- retrospective or read-only mode

This is the primary place for control-state messaging.

### 4.3 Action strip

Use for:

- the 1-4 main actions for the page

Do not mix:

- primary task actions
- destructive actions
- low-priority utility links

Those should be visually distinguished.

### 4.4 Filter bar

Use on queue/index pages.

Must show:

- active scope
- active business date or date range
- easy clear/reset path

### 4.5 Data table or operational list

Default choice for:

- queues
- indexes
- review surfaces

Prefer tables or structured lists over repeated summary cards when the operator is comparing many rows.

### 4.6 Support panel

Use only for genuinely secondary information:

- related links
- definitions
- side notes

Support panels should not compete visually with core workflow content.

---

## 5. Navigation Framework

### 5.1 Global navigation

The current internal top nav already separates `Home`, `Branch`, `Ops`, and `Admin`.

Keep this as the workspace switcher.

Its job is:

- switch workspace
- reinforce operator identity
- show current business date context

Its job is not:

- deep navigation inside a workflow

### 5.2 Workspace navigation

Each workspace should use task-led navigation, not document-site navigation.

#### Branch

Branch navigation should reflect operator intent:

- `Today`
- `Customers`
- `Teller`
- `Supervisor`
- `Cash`
- `Events`

Current branch surface nav is directionally correct but still section-oriented. It should feel more like operational lanes than page categories.

#### Ops

Ops navigation should reflect control and evidence:

- `Close package`
- `Events`
- `Exceptions`
- `Cash`
- `Engines`
- `Projections`

Ops should feel like a control console, not a dashboard gallery.

### 5.3 In-page navigation

Avoid using in-page anchors as primary workflow navigation except for long reference pages.

Anchors are acceptable as convenience helpers, not as the main drill contract.

---

## 6. Visual Hierarchy Rules

### 6.1 One primary thing per page

Every page must make one thing visually dominant:

- the transaction being performed
- the queue being reviewed
- the record being explained
- the control state being evaluated

If several sections look equally important, hierarchy has failed.

### 6.2 Do not card everything

Use cards sparingly for:

- compact status summaries
- clearly separated supporting modules

Do not wrap every form block, list, and explanatory paragraph in the same card treatment.

### 6.3 Use tables for comparison, not stacked boxes

When the user compares rows, tables or aligned lists beat tiles.

This applies especially to:

- teller sessions
- operational events
- approvals
- holds

### 6.4 Make warnings and blockers unmistakable

Blockers, warnings, and read-only modes should not share the same visual weight as ordinary summaries.

---

## 7. Alerts and Feedback

### 7.1 No layout jump after submit

Flash alerts should not push the page content downward unpredictably.

Preferred pattern:

- reserve a stable feedback region near the top of the content area, or
- use toast-like success confirmations for routine success while keeping form errors inline

### 7.2 Error placement

Use:

- field-level errors next to problematic inputs
- one form-level error summary above the form

Do not rely on a global alert alone for form validation failures.

### 7.3 Success placement

Routine success should confirm completion without disorienting the operator.

For multi-step or high-risk actions, combine:

- a success confirmation
- a stable result or receipt area

---

## 8. Operational State Model

The UI should treat certain states as first-class UX drivers, not merely as small status badges.

### 8.1 Business-date state

Relevant screens should clearly distinguish:

- current open business date
- reviewed historical date
- posting still open vs closed

This is especially important on:

- close package
- EOD screens
- event search and event detail when date context matters
- transaction flows that depend on the open day

### 8.2 Teller-session state

Relevant screens should clearly distinguish:

- no session selected
- open session
- pending-supervisor session
- closed session

Teller-session context is not a secondary implementation detail. It is part of the operating state of teller work.

### 8.3 Posting or record state

Relevant screens should clearly distinguish:

- pending
- posted
- reversed
- informational no-GL states where applicable

Operators should not need to infer the record state from secondary copy or buried metadata.

### 8.4 Approval state

Relevant screens should clearly distinguish:

- no approval required
- approval required
- pending approval
- approved

This framework does not assume time-window expiries or countdown timers unless the underlying product flow actually supports them.

---

## 9. Button and Interaction-State Framework

### 8.1 Button roles

Use a small semantic set:

- `Primary`: main action on the page
- `Secondary`: supporting action
- `Danger`: destructive or high-risk action
- `Quiet`: navigation or utility action

### 8.2 State requirements

Every actionable control should visibly support:

- default
- hover/focus
- active/pressed
- disabled
- pending/submitting

### 8.3 Do not make destructive actions look routine

Examples:

- reversals
- business-date close
- variance approval with posting effect

These need stronger affordance than a generic bordered button.

### 8.4 Do not let clicked state disappear

After submit, the operator should be able to tell:

- that the click registered
- that work is in progress
- whether the action completed

---

## 10. Form Framework

### 9.1 Internal forms are workflows, not CRUD sheets

A good internal transaction form usually has these sections:

1. `Task context`
2. `Subject or account context`
3. `Transaction inputs`
4. `Warnings or policy notes`
5. `Review and submit`

### 9.2 Required structure

Every transaction form should answer:

- What am I doing?
- For which account or party?
- Under which teller session or operating unit, if applicable?
- What inputs are required?
- What will happen when I submit?

### 9.3 Reduce optional-field noise

Advanced or rarely used fields should not crowd the core path.

Examples:

- idempotency helpers
- reference IDs
- secondary notes

These may still need to be present, but they should not dominate the screen.

### 9.4 Keep context visible while entering data

For account- or session-based transactions, the relevant context should stay near the form:

- account number and product
- customer name
- teller session
- current business date

The user should not need to scroll back to remember what they are acting on.

### 10.5 Teller transaction requirements

Teller-facing transaction forms need stronger guidance than generic internal forms.

At minimum they should keep visible:

- account context
- current business date
- teller session, where applicable
- operating unit, where applicable

For cash-affecting teller flows, the form should also make the transaction effect legible before submit.

Examples:

- money in vs money out
- fee effect where relevant
- resulting drawer or session impact where the system can compute it reliably

This framework does not require a universal real-time simulation widget on every form. It does require that cash-affecting forms reduce submission ambiguity and expose the effect of the transaction clearly enough for safe operation.

### 10.6 Approval-aware forms

If a form initiates an approval-sensitive action, the form should make that plain before submit.

Examples:

- supervisor approval required
- action will enter a pending approval state
- action is immediately final

The operator should not discover approval semantics only after submission.

---

## 11. Record Traceability Standard

Financial and operational record pages should support complete explanation of what happened.

### 11.1 Required traceability chain

Where applicable, a record detail page should expose:

1. operational narrative
2. posting impact
3. affected accounts or subledgers
4. related records such as reversals or linked events
5. source channel or originating surface

For event-backed records, this often means:

- operational event
- posting batch
- journal entry
- journal lines
- related account context

### 11.2 Reversal visibility

Where a record can be reversed or has been reversed, the linkage should be easy to understand:

- reversal of
- reversed by
- current status after reversal

Reversal linkage should not be buried as an obscure metadata field on financial-detail pages.

### 11.3 GL impact explainability

If a record affects the ledger, the operator should be able to answer:

- what moved
- which accounts were affected
- whether the record posted successfully

This does not mean every Branch detail page must duplicate the full Ops journal grid. It does mean the system should expose a traceable path to that truth.

---

## 12. Cash Context and Queue Guidance

### 12.1 Cash context block

On cash-sensitive screens, the UI should show cash context explicitly rather than treating cash as an abstract amount.

Depending on the screen, this may include:

- cash location
- operating unit
- drawer or vault relationship
- current balance or relevant count summary

This is most important for:

- cash approvals
- cash reconciliation
- teller-session and drawer-sensitive work
- shipment or transfer flows

It is not required on every screen in the application.

### 12.2 Queue intelligence

Queues should help operators identify what needs attention first.

At minimum, queue screens should support:

- created-at or age visibility
- clear operational state
- obvious next action

Where product rules support it, queues may also show:

- higher-risk amounts
- exception severity
- escalation or approval-needed indicators

This framework does not require invented priority scoring when the product does not define one.

---

## 13. Data-Dense Screen Guidance

### 10.1 Ops event search

Should be the model queue/index page:

- context banner
- filter bar
- table
- clear drill actions

This screen is closer to the desired pattern than most others.

### 10.2 Close package

Should remain a hub page, not become a giant wall of boxes.

Guidance:

- one dominant control-state area at top
- summary counts with clear drillability
- evidence sections beneath
- reduce equal-weight treatment across all sections

### 10.3 Branch dashboard

Should prioritize "what should I do next?" over "show every possible area."

Guidance:

- current-day orientation first
- primary branch tasks second
- queue-like pending work third
- dense session details lower on the page or on dedicated screens

---

## 14. Current Screen Mapping

This table maps shipped screens to target patterns.

| Screen | Current role | Target page type | Main UX issue |
| --- | --- | --- | --- |
| `branch/dashboard` | mixed dashboard + queue + action launcher | hub page | too many equal-weight sections and cards |
| `branch/operational_events` | event list | queue/index | adequate shape, but filter/action hierarchy can tighten |
| `branch/operational_events/:id` | event detail | record detail | action-oriented but missing some parity and clearer fact grouping |
| `branch/customers` | search | queue/index | closer to desired shape |
| `branch/deposits/new` | transaction form | transaction form | needs stronger workflow grouping and clearer submit affordance |
| `branch/withdrawals/new` | transaction form | transaction form | same as above |
| `branch/check_deposits/new` | transaction form | transaction form | high cognitive load; likely needs the strongest workflow treatment |
| `branch/reversals/new` | transaction form | transaction form | danger state and policy context need to be more obvious |
| `branch/cash` | mixed summary + launcher | hub page | could use clearer split between current position and next actions |
| `ops` | workspace launcher | hub page | tile gallery is acceptable but still generic |
| `ops/close_package` | control surface | hub page | too many same-weight sections; needs stronger hierarchy |
| `ops/operational_events` | event search | queue/index | strongest current pattern; use as reference |
| `ops/operational_events/:id` | event detail | record detail | strong structural baseline |
| `ops/exceptions` | workflow queue | queue/index | should lean harder into queue treatment over cards |
| `ops/cash` | approval queue | queue/index | currently closer to stacked cards than a true queue |

---

## 15. Recommended Refactor Order

### 15.1 Framework first

Create shared patterns for:

- page headers
- operational context strips
- status banners
- action strips
- filter bars
- flash region
- button variants
- form sections

### 15.2 High-traffic Branch screens second

Prioritize:

1. Branch dashboard
2. Deposit form
3. Withdrawal form
4. Check deposit form
5. Reversal form

These likely drive most of the perceived friction.

Focus:

- stable context
- form clarity
- cash-effect legibility
- stronger action states

### 15.3 Ops polish third

Prioritize:

1. Close package hierarchy cleanup
2. Exceptions queue treatment
3. Cash approvals/reconciliation clarity

Focus:

- control-state hierarchy
- queue clarity
- evidence drillability

### 15.4 Shared detail-page consistency fourth

Standardize:

- record fact sections
- action placement
- related-link grouping
- drilldown affordances
- traceability blocks

Priority targets:

1. Ops operational event detail
2. Branch operational event detail
3. future teller session detail
4. account and cash detail surfaces

---

## 16. Acceptance Heuristics

A screen is improving if:

- an operator can identify the page's main purpose within a few seconds
- the current operational context is visible when it matters
- alerts do not shift the working area unpredictably
- the primary action is obvious
- form completion order feels guided rather than guessed
- active filters and scope are visible
- destructive actions are unmistakable
- record state is understandable without hunting through metadata
- financial or approval-sensitive screens are explainable after the fact
- tables are used where comparison matters
- secondary content does not compete with the main task

If a redesign adds polish but still makes the operator read everything to know what to do, it has not solved the real problem.

---

## 17. Implementation Notes

- Prefer shared partials and helpers over one-off styling fixes.
- Preserve current domain/query/controller boundaries from ADR-0025 and ADR-0037.
- Keep current business-date and drilldown semantics consistent with ADR-0042.
- Do not imply product behaviors the system does not actually support yet, such as approval expiry timers or denomination-aware cash UX.
- Treat this as an internal UX operating model, not a final visual spec. Specific CSS and component implementations may evolve as long as they preserve the page-type and interaction rules above.
