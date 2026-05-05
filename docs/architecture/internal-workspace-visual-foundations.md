# Internal Workspace Visual Foundations

**Status:** Draft  
**Scope:** Internal `branch`, `ops`, and `admin` workspaces  
**Aligns with:** [internal-workspace-ux-framework.md](internal-workspace-ux-framework.md), [ADR-0025](../adr/0025-internal-workspace-ui.md), [ADR-0037](../adr/0037-internal-staff-authorized-surfaces.md), [ADR-0042](../adr/0042-business-date-monitoring-and-drilldown-surfaces.md)

---

## 1. Purpose

This document defines the basic visual rules for BankCORE's internal UI:

- colors
- typography
- spacing
- action emphasis
- semantic state styling

The goal is not originality. The goal is operational clarity.

For an internal banking UI, "good visual design" means:

- readable at speed
- predictable
- calm
- clear about risk and state

---

## 2. Design Direction

BankCORE internal UI should feel:

- restrained
- serious
- legible
- stable

Avoid:

- decorative color variety
- card-heavy page layouts
- soft, generic consumer-app styling
- overly light text or tiny typography

The visual baseline should be:

- neutrals for most of the UI
- one dark accent for actions and active navigation
- semantic colors only for meaning

---

## 3. Fonts

### 3.1 Primary font

Use a legible sans-serif stack for the entire internal UI.

Recommended stack:

- `Inter`
- fallback to system sans

Why:

- clean numerals
- compact without feeling cramped
- strong readability in forms and tables
- neutral, modern tone

### 3.2 Alternative acceptable fonts

If `Inter` is not desired later, acceptable alternatives are:

- `IBM Plex Sans`
- `Source Sans 3`

Do not introduce expressive display fonts for internal workspaces.

### 3.3 Typography rules

Use a small, consistent hierarchy:

- page title: `text-3xl font-semibold`
- section title: `text-xl font-semibold`
- sub-section or panel title: `text-sm font-medium` or `text-base font-medium`
- body copy: `text-sm` or `text-base`
- help text: `text-sm text-slate-600`
- metadata: `text-xs text-slate-500`

Avoid two common mistakes:

- everything too small
- everything too bold

---

## 4. Color System

### 4.1 Base neutrals

Neutrals should do most of the work.

Recommended baseline:

- page background: `slate-100`
- surface background: `white`
- muted surface: `slate-50`
- default border: `slate-200`
- stronger divider: `slate-300`
- primary text: `slate-950`
- secondary text: `slate-600`
- tertiary text: `slate-500`

This creates a calm internal-app baseline without making the UI feel washed out.

### 4.2 Primary action color

Use one dark action accent consistently.

Recommended baseline:

- primary action / active nav: `slate-900`
- hover: `slate-800`
- focus ring: `slate-700`

This is intentionally conservative. It makes primary actions and active states obvious without introducing a flashy brand accent.

### 4.3 Semantic state colors

Use semantic colors only for meaning.

#### Success

- background: `emerald-50`
- border: `emerald-200`
- text: `emerald-800`

#### Warning

- background: `amber-50`
- border: `amber-200`
- text: `amber-900`

#### Danger

- background: `red-50`
- border: `red-200`
- text: `red-800`

#### Info / context

- background: `blue-50`
- border: `blue-200`
- text: `blue-900`

Do not use these as general decoration. They should signal meaning, not visual variety.

---

## 5. Spacing

Spacing is usually a bigger clarity problem than color.

Recommended rhythm:

- page padding: `px-6 py-8`
- major section spacing: `mt-8` or `mt-10`
- panel padding: `p-5` or `p-6`
- standard form gap: `gap-4`
- dense metadata gap: `gap-2`
- table cell padding: `px-4 py-3` or `px-5 py-4`

If a screen feels messy, check spacing before adding more borders or color.

---

## 6. Buttons

Use only a few semantic button roles.

### 6.1 Primary

Use for the main action on the page.

Recommended style:

- dark filled background
- white text

Example direction:

- `bg-slate-900 text-white hover:bg-slate-800`

### 6.2 Secondary

Use for supporting actions.

Recommended style:

- white background
- border
- dark text

### 6.3 Danger

Use for:

- reversals
- close actions
- destructive or high-risk confirmations

Recommended style:

- red filled or strong red-outline treatment

Danger actions must not look like ordinary navigation.

### 6.4 Quiet

Use for utility or navigation actions that should not compete with the main action.

Recommended style:

- ghost or text-like treatment

### 6.5 Required states

Every button role should visibly support:

- default
- hover/focus
- active/pressed
- disabled
- pending/submitting

Operators must be able to tell when an action has been clicked and when the system is still processing.

---

## 7. Panels and Surfaces

Use fewer surface styles, each with a clear job.

### 7.1 Normal panel

Use for standard sections:

- white background
- light border
- minimal shadow if any

### 7.2 Tinted banner

Use for:

- blocker/warning messaging
- retrospective mode
- success/error state

### 7.3 Table or structured list

Use for:

- operational comparisons
- queues
- event indexes
- approvals

Do not replace tables with grids of similar-looking cards.

### 7.4 Support panel

Use only for secondary information:

- definitions
- supporting links
- lower-priority notes

It should not compete visually with the core workflow area.

---

## 8. Navigation States

Navigation needs stronger state expression than generic bordered pills.

### 8.1 Global workspace nav

Should clearly distinguish:

- active workspace
- inactive workspace
- focus state

### 8.2 Branch surface nav

Should feel like operational lanes, not arbitrary tabs.

Make active state unmistakable through:

- filled background
- stronger contrast
- consistent active treatment across surfaces

---

## 9. Forms

Visual design should support workflow clarity.

### 9.1 Form structure

Use clear sections with visible headings and short descriptions:

- task context
- subject/account/session context
- inputs
- warnings/review
- submit area

### 9.2 Context visibility

On teller and branch forms, keep relevant context near the form:

- business date
- account
- operating unit
- teller session
- cash location, when relevant

### 9.3 Reduce noise

Optional or advanced fields should not crowd the main task path.

---

## 10. Alerts and Feedback

### 10.1 Stable placement

Feedback should not cause large layout shifts.

Recommended pattern:

- one stable flash region near the top of internal content

### 10.2 Routine success

Routine success should confirm without overwhelming the page.

### 10.3 Errors

Use:

- field-level errors
- one clear form-level error summary

Do not rely only on global alerts for validation failures.

---

## 11. Starter Token Set

BankCORE now has a starter token block in:

- [app/assets/tailwind/application.css](/Users/syckot/CursorProjects/bankcore-4/app/assets/tailwind/application.css)

Current tokens include:

- font stack
- background and surface colors
- border colors
- text colors
- primary action color
- semantic success/warning/danger/info colors
- base spacing tokens

These tokens are intentionally simple. They are a foundation for shared partials and helpers, not a full design system by themselves.

---

## 12. Practical Defaults

If you are unsure, use these defaults:

- font: `Inter`, fallback system sans
- page background: `slate-100`
- section surface: `white`
- border: `slate-200`
- primary text: `slate-950`
- secondary text: `slate-600`
- primary action: `slate-900`
- success: `emerald`
- warning: `amber`
- danger: `red`

This is intentionally conservative. For BankCORE internal UI, conservative is a strength.

---

## 13. What Not To Do

Avoid:

- multiple accent colors competing on the same page
- heavy reliance on shadows
- wrapping every section in the same card treatment
- tiny text for operational details
- using semantic colors as decoration
- introducing another component framework just to get prettier widgets

---

## 14. Next Steps

Apply these foundations through the shared internal UI layer:

- helpers for button, badge, nav, and panel classes
- shared partials for page headers, context strips, status banners, and form sections
- stable flash region in the internal layout

This gives BankCORE a consistent internal visual language without adding a second frontend framework.
