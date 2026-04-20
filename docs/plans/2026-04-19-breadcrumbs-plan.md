---
title: "feat: Replace back arrows with breadcrumb navigation"
type: feat
status: active
date: 2026-04-19
origin: docs/plans/2026-04-19-breadcrumbs-design.md
---

# feat: Replace back arrows with breadcrumb navigation

## Overview

Replace all back arrow buttons (desktop toolbar arrows + mobile floating FABs) with breadcrumb navigation showing the user's position in the hierarchy: Organization → Family → Page. Each ancestor segment is a navigable link. The breadcrumb preserves existing contextual routing (e.g., person page changes based on `from_family` / `from_org`).

## Problem Frame

Back arrows tell users "go back" but not **where** they're going. Breadcrumbs show the full navigation path, making the hierarchy explicit. This change affects all pages that currently display a back arrow — 12 templates total, plus mobile FABs in 8 of them.

(See origin: `docs/plans/2026-04-19-breadcrumbs-design.md`)

## Requirements Trace

- R1. Every page with a back arrow gets a breadcrumb showing the path from org to current page
- R2. Desktop: breadcrumb inline in toolbar, replacing the back arrow, with the current page as the last bold segment
- R3. Mobile: page title bold on top, ancestor breadcrumb trail as small text below — replaces the hamburger+title layout in the toolbar
- R4. All mobile FAB back buttons removed
- R5. Person page preserves contextual routing (`from_family` → family in trail, `from_org` → People in trail, default → org only)
- R6. Long names truncate with ellipsis to prevent overflow
- R7. Existing E2E tests updated to use breadcrumb test IDs

## Scope Boundaries

- Pages without back arrows are not touched (organization_live/index, family_live/index, person_live/index)
- The hamburger menu button on mobile remains — it opens the nav drawer which is separate from breadcrumbs
- No changes to the nav drawer component itself
- No changes to routing or URL structure

## Context & Research

### Relevant Code and Patterns

- **Toolbar pattern**: Every page uses `<:toolbar>` slot with a consistent structure: `flex items-center justify-between` wrapper, left side has hamburger (mobile) + back arrow (desktop) + title, right side has actions
- **Desktop back arrow**: `<.link navigate={...} class="hidden lg:flex ...">` with `hero-arrow-left` icon
- **Mobile FAB**: `<.link navigate={...} class="fixed bottom-4 left-4 z-30 ... lg:hidden">` with `hero-arrow-left` icon
- **Person page**: Uses `cond` block with `@from_family` / `@from_org` / `true` for conditional back routing — both in desktop toolbar and mobile FAB sections
- **Title rendering**: Most pages show `<h1>` always visible. Person page shows title `hidden lg:block` (mobile has it on the hero photo section)
- **Design tokens**: `text-ds-on-surface-variant` for muted text, `text-ds-on-surface` for primary text, `font-ds-heading` for headings

### Institutional Learnings

- `mobile-toolbar-pattern`: Pick one toolbar pattern and apply it everywhere. Wrap desktop actions in `hidden lg:flex`
- `pure-presentation-components`: Make reusable components pure presentation — let call sites decide navigation behavior
- `template-struct-field-blind-spot`: Always verify schema field names before referencing in templates

## Key Technical Decisions

- **Component in `core_components.ex`**: Add a `breadcrumb/1` function component rather than a separate file — it's a small, widely-used UI primitive like `header/1` or `table/1`. Takes `items` (list of maps with `:label` and `:navigate`) and `current` (string for current page title)
- **Desktop: all-inline breadcrumb**: Renders `Org / Family / Current Page` where ancestors are links and current page is bold text. Replaces both the back arrow and the `<h1>` title
- **Mobile: stacked title + trail**: Renders the page title as bold text on the first line, with the ancestor trail as small muted links below. This replaces both the title and the back arrow in the toolbar area. The hamburger stays to the left
- **Separator rendering**: Use `/` character with `text-ds-on-surface-variant` styling, inline with `mx-1` spacing
- **No separate mobile breadcrumb component**: Same `<.breadcrumb>` component handles both layouts using responsive classes internally

## Open Questions

### Resolved During Planning

- **Where to put the component?** In `core_components.ex` after the `header/1` component — follows existing pattern of small shared UI primitives
- **Should vault/memory pages get breadcrumbs?** Yes — vault_live/show, memory_live/show, memory_live/form all have back arrows
- **What about memory_live/form edit vs new?** The breadcrumb trail changes: new goes back to vault, edit goes back to memory. Both use the same component, just different `items`

### Deferred to Implementation

- Exact truncation behavior for very long org/family names on narrow screens — will tune with `max-w` and `truncate` classes during implementation

## Implementation Units

- [ ] **Unit 1: Create `breadcrumb/1` component in core_components.ex**

  **Goal:** Add a reusable breadcrumb component that all pages will use

  **Requirements:** R2, R3, R6

  **Dependencies:** None

  **Files:**
  - Modify: `lib/web/components/core_components.ex`

  **Approach:**
  - Add `breadcrumb/1` function component after the `header/1` component
  - Accepts `items` attr (list of `%{label, navigate}` maps) and `current` attr (string)
  - Desktop layout (`hidden lg:flex`): renders items as links with `/` separators, then current page as bold text
  - Mobile layout (`lg:hidden`): renders current as bold title, items below as small linked trail
  - Use `text-ds-on-surface-variant` for separators and ancestor links, `text-ds-on-surface` with `font-semibold` for current
  - Apply `truncate` on individual segments to handle long names
  - The hamburger button is NOT part of this component — it stays in each template

  **Patterns to follow:**
  - Existing `header/1` component in `core_components.ex` for attr declarations and slot patterns
  - Design token usage from existing toolbar markup

  **Test scenarios:**
  - Component renders ancestor links with correct `navigate` paths
  - Component renders current page as non-linked bold text
  - Desktop renders all-inline; mobile renders stacked
  - Empty items list renders just the current page title
  - Single item renders one ancestor link + current

  **Verification:**
  - Component compiles without warnings
  - Can be invoked in a template with `<.breadcrumb items={[...]} current="Page" />`

- [ ] **Unit 2: Replace back arrows in family_live/show**

  **Goal:** Replace desktop back arrow and mobile FAB with breadcrumb

  **Requirements:** R1, R2, R3, R4

  **Dependencies:** Unit 1

  **Files:**
  - Modify: `lib/web/live/family_live/show.html.heex`

  **Approach:**
  - Remove desktop back arrow `.link` (lines 15-23)
  - Remove mobile FAB (lines 175-182)
  - Replace the `<h1>` title with `<.breadcrumb items={[org_item]} current={@family.name} />`
  - `org_item` = `%{label: @current_scope.organization.name, navigate: ~p"/org/#{@current_scope.organization.id}"}`

  **Patterns to follow:**
  - Keep the existing toolbar wrapper div structure and actions on the right side

  **Test scenarios:**
  - Breadcrumb shows `Org Name / Family Name` with org as link
  - No back arrow or FAB visible
  - Desktop actions still present on the right

  **Verification:**
  - Page renders without errors
  - Breadcrumb links to org index

- [ ] **Unit 3: Replace back arrows in gallery_live/show**

  **Goal:** Replace desktop back arrow and mobile FAB with breadcrumb

  **Requirements:** R1, R2, R3, R4

  **Dependencies:** Unit 1

  **Files:**
  - Modify: `lib/web/live/gallery_live/show.html.heex`

  **Approach:**
  - Remove desktop back arrow (lines 14-21)
  - Remove mobile FAB (lines 109-116)
  - Replace `<h1>` with `<.breadcrumb items={[org_item, family_item]} current={@gallery.name} />`

  **Test scenarios:**
  - Breadcrumb shows `Org / Family / Gallery` with first two as links

  **Verification:**
  - Page renders, breadcrumb navigates correctly

- [ ] **Unit 4: Replace back arrows in person_live/show**

  **Goal:** Replace conditional back arrows (desktop + mobile FAB) with contextual breadcrumb

  **Requirements:** R1, R2, R3, R4, R5

  **Dependencies:** Unit 1

  **Files:**
  - Modify: `lib/web/live/person_live/show.html.heex`

  **Approach:**
  - Remove the entire `cond` block for desktop back arrows (lines 15-45)
  - Remove the entire `cond` block for mobile FABs (lines 120-151)
  - Build breadcrumb items conditionally based on `@from_family` / `@from_org`:
    - `@from_family`: `[org, %{label: @from_family.name, navigate: family_path_with_person_param}]`
    - `@from_org`: `[org, %{label: gettext("People"), navigate: org_people_path}]`
    - default: `[org]`
  - Replace the `<h1>` (currently `hidden lg:block`) with the breadcrumb component
  - Current = `Ancestry.People.Person.display_name(@person)`
  - Note: person page shows the name on the hero photo section on mobile — the breadcrumb mobile layout will also show it in the toolbar, which is fine (provides consistent breadcrumb behavior)

  **Test scenarios:**
  - From family: breadcrumb shows `Org / Family / Person`
  - From org people: breadcrumb shows `Org / People / Person`
  - Default: breadcrumb shows `Org / Person`
  - Family link includes `?person=` param to highlight on return

  **Verification:**
  - All three context paths render correct breadcrumb trail

- [ ] **Unit 5: Replace back arrows in kinship_live, people_live/index, org_people_live/index**

  **Goal:** Replace back arrows and FABs for the three remaining family-scoped and org-scoped index pages

  **Requirements:** R1, R2, R3, R4

  **Dependencies:** Unit 1

  **Files:**
  - Modify: `lib/web/live/kinship_live.html.heex`
  - Modify: `lib/web/live/people_live/index.html.heex`
  - Modify: `lib/web/live/org_people_live/index.html.heex`

  **Approach:**
  - **kinship_live**: `items=[org, family]`, `current=gettext("Kinship")`
  - **people_live/index**: `items=[org, family]`, `current=gettext("People")`. Currently shows `@family.name — People` as title; breadcrumb replaces this with `Org / Family / People`
  - **org_people_live/index**: `items=[org]`, `current=gettext("People")`
  - Remove FABs from all three

  **Test scenarios:**
  - Each page shows correct breadcrumb hierarchy
  - No FABs visible

  **Verification:**
  - All three pages render correctly with breadcrumbs

- [ ] **Unit 6: Replace back arrows in family_live/new, person_live/new**

  **Goal:** Replace back arrows and FABs for the two "new" form pages

  **Requirements:** R1, R2, R3, R4

  **Dependencies:** Unit 1

  **Files:**
  - Modify: `lib/web/live/family_live/new.html.heex`
  - Modify: `lib/web/live/person_live/new.html.heex`

  **Approach:**
  - **family_live/new**: `items=[org]`, `current=gettext("New Family")`
  - **person_live/new**: `items=[org, family]`, `current=gettext("New Member")`
  - Remove FABs from both

  **Test scenarios:**
  - New family shows `Org / New Family`
  - New member shows `Org / Family / New Member`

  **Verification:**
  - Both form pages render with breadcrumbs, no FABs

- [ ] **Unit 7: Replace back arrows in vault_live/show, memory_live/show, memory_live/form**

  **Goal:** Replace back arrows for the vault/memory pages

  **Requirements:** R1, R2, R3, R4

  **Dependencies:** Unit 1

  **Files:**
  - Modify: `lib/web/live/vault_live/show.html.heex`
  - Modify: `lib/web/live/memory_live/show.html.heex`
  - Modify: `lib/web/live/memory_live/form.html.heex`

  **Approach:**
  - **vault_live/show**: `items=[org, family]`, `current=@vault.name`. Note: no hamburger/responsive split on this page — just a plain back arrow. Add the same breadcrumb pattern
  - **memory_live/show**: `items=[org, family, vault]`, `current=@memory.name`
  - **memory_live/form**: Conditional based on `@live_action`:
    - `:new` → `items=[org, family, vault]`, `current=gettext("New Memory")`
    - `:edit` → `items=[org, family, vault, memory]`, `current=gettext("Edit Memory")`
  - No FABs on these pages (they don't have them)

  **Test scenarios:**
  - Vault shows `Org / Family / Vault Name`
  - Memory show: `Org / Family / Vault / Memory Name`
  - Memory new: `Org / Family / Vault / New Memory`
  - Memory edit: `Org / Family / Vault / Memory Name / Edit Memory`

  **Verification:**
  - All three pages render with correct breadcrumbs

- [ ] **Unit 8: Update E2E tests**

  **Goal:** Update existing tests that reference back button test IDs

  **Requirements:** R7

  **Dependencies:** Units 2-7

  **Files:**
  - Modify: `test/user_flows/create_family_test.exs`
  - Modify: `test/user_flows/org_manage_people_test.exs`
  - Modify: `test/user_flows/gallery_back_button_after_lightbox_test.exs`

  **Approach:**
  - `create_family_test.exs:62`: Currently clicks `test_id("family-back-btn")` — update to click the org breadcrumb link instead (use a breadcrumb test ID or navigate link)
  - `org_manage_people_test.exs:245`: Currently clicks `test_id("person-back-btn")` — update similarly
  - `gallery_back_button_after_lightbox_test.exs`: Tests FAB visibility/clicking `#gallery-back-fab` — this test may need significant rework or removal since FABs are gone. The underlying behavior (navigation after lightbox) should still be testable via breadcrumb clicks
  - Add `test_id("breadcrumb")` to the breadcrumb component for easy test targeting

  **Test scenarios:**
  - All existing navigation flows still work via breadcrumb clicks
  - No references to removed back button test IDs

  **Verification:**
  - `mix test` passes with no failures
  - `mix precommit` passes

## System-Wide Impact

- **Toolbar structure**: Every page's `<:toolbar>` section is modified. The left side changes from `hamburger + back arrow + title` to `hamburger + breadcrumb`. Right side (actions) is untouched
- **Mobile FABs**: 8 pages lose their fixed-position back FABs, freeing up the bottom-left corner of the viewport
- **Person page hero**: The person page shows the name on the hero photo section on mobile. With breadcrumbs, the name will also appear in the toolbar breadcrumb. This is acceptable — the toolbar breadcrumb provides navigation context while the hero is decorative
- **Test IDs**: Back button test IDs (`*-back-btn`, `*-back-fab`) are removed. Breadcrumb gets its own test ID
- **Accessibility**: Back arrows had `aria-label` like "Back to families". Breadcrumb links are self-describing via their text content, which is better for screen readers

## Risks & Dependencies

- **Visual regression on person page mobile**: The person page has a unique mobile layout where the title is on the hero photo, not in the toolbar. Adding breadcrumb to toolbar means the name appears twice on mobile. May need to keep the toolbar breadcrumb title hidden on mobile for this specific page, or accept the duplication
- **Test breakage**: 3 test files reference back button test IDs — must update in Unit 8

## Sources & References

- **Origin document:** [docs/plans/2026-04-19-breadcrumbs-design.md](docs/plans/2026-04-19-breadcrumbs-design.md)
- Related code: `lib/web/components/core_components.ex` (component home), `lib/web/components/layouts.ex` (toolbar slot)
- Learning: `mobile-toolbar-pattern` — standardize toolbar structure across pages
