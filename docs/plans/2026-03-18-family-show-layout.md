# Family Show Layout Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Restructure the Family Show page to use a full-width edge-to-edge layout with a horizontally-scrollable tree view and fixed-width sidebar, with sidebar on top on mobile.

**Architecture:** Remove global padding from `<main>` in the app layout. Replace the Family Show flexbox layout with CSS grid (`1fr + 18rem`). Use CSS `order` classes to swap sidebar/tree position on mobile. Constrain horizontal scroll to the tree canvas container only.

**Tech Stack:** Phoenix LiveView, Tailwind CSS v4, HEEx templates

**Design doc:** `docs/plans/2026-03-18-family-show-layout-design.md`

---

### Task 1: Remove padding from Layouts.app `<main>`

**Files:**
- Modify: `lib/web/components/layouts.ex:77`

**Step 1: Update the `<main>` tag**

In `lib/web/components/layouts.ex`, change line 77 from:

```elixir
<main class="px-4 sm:px-6 lg:px-8 pt-8 min-h-100">
```

to:

```elixir
<main class="min-h-100">
```

**Step 2: Run existing tests to verify nothing breaks**

Run: `mix test`
Expected: All existing tests pass. Some tests may assert on text content that still renders fine without the padding.

**Step 3: Commit**

```
git add lib/web/components/layouts.ex
git commit -m "Remove padding from main layout for edge-to-edge pages"
```

---

### Task 2: Restructure Family Show template to CSS grid layout

**Files:**
- Modify: `lib/web/live/family_live/show.html.heex:28-103`

**Step 1: Replace the flex container with a CSS grid container**

In `lib/web/live/family_live/show.html.heex`, replace the outer `<div>` at line 28:

```heex
<div class="flex flex-col lg:flex-row">
```

with:

```heex
<div class="grid grid-cols-1 lg:grid-cols-[1fr_18rem] overflow-x-hidden">
```

**Step 2: Wrap the sidebar in an order-controlled div and move it before the tree canvas**

Move the `SidePanelComponent` (lines 94-102) above the tree canvas div (lines 29-92) and wrap it in a div with order classes and border classes:

```heex
<div class="grid grid-cols-1 lg:grid-cols-[1fr_18rem] overflow-x-hidden">
  <%!-- Side Panel: first on mobile, last on desktop --%>
  <div class="order-first lg:order-last border-b lg:border-b-0 lg:border-l border-base-200">
    <.live_component
      module={Web.FamilyLive.SidePanelComponent}
      id="side-panel"
      galleries={@galleries}
      people={@people}
      family_id={@family.id}
      focus_person_id={@focus_person && @focus_person.id}
    />
  </div>

  <%!-- Tree Canvas: last on mobile, first on desktop --%>
  <div
    id="tree-canvas"
    class="overflow-x-auto p-6 order-last lg:order-first"
    phx-hook=".ScrollToFocus"
  >
    <%!-- ...existing tree content (lines 35-91 unchanged)... --%>
  </div>
</div>
```

Key changes:
- Sidebar div is first in DOM, uses `order-first lg:order-last`
- Tree canvas div is second in DOM, uses `order-last lg:order-first`
- Tree canvas: `overflow-x-scroll` replaced with `overflow-x-auto`, `overflow-y-visible` removed, `flex-1` removed
- Grid container has `overflow-x-hidden` to prevent full-page horizontal scroll

**Step 3: Run tests**

Run: `mix test test/web/live/family_live/show_test.exs`
Expected: All tests pass — the DOM IDs and elements haven't changed, only the CSS layout.

**Step 4: Commit**

```
git add lib/web/live/family_live/show.html.heex
git commit -m "Restructure Family Show to CSS grid layout with sidebar order swap"
```

---

### Task 3: Simplify SidePanelComponent classes

**Files:**
- Modify: `lib/web/live/family_live/side_panel_component.ex:12-16`

**Step 1: Remove width and border classes from the aside**

In `lib/web/live/family_live/side_panel_component.ex`, replace the class list on the `<aside>` tag:

```elixir
class={[
  "border-l border-base-200 bg-base-100 flex flex-col p-4 gap-6",
  "w-72 lg:w-72",
  "max-lg:w-full max-lg:border-l-0 max-lg:border-t"
]}
```

with:

```elixir
class="bg-base-100 flex flex-col p-4 gap-6"
```

The parent grid cell in `show.html.heex` now controls the width (18rem on desktop, full-width on mobile) and borders.

**Step 2: Run tests**

Run: `mix test test/web/live/family_live/show_test.exs`
Expected: All tests pass.

**Step 3: Commit**

```
git add lib/web/live/family_live/side_panel_component.ex
git commit -m "Simplify SidePanelComponent classes, parent grid controls sizing"
```

---

### Task 4: Update ScrollToFocus hook for horizontal-only scroll

**Files:**
- Modify: `lib/web/live/family_live/show.html.heex` (the colocated hook at lines 284-307)

**Step 1: Update the hook to only scroll horizontally within the container**

Replace the `scrollToFocus()` method in the `.ScrollToFocus` colocated hook:

```javascript
scrollToFocus() {
  setTimeout(() => {
    const target = this.el.querySelector("#focus-person-card")
    if (!target) return

    const container = this.el
    const targetRect = target.getBoundingClientRect()
    const containerRect = container.getBoundingClientRect()

    // Horizontal scroll within the tree canvas container
    container.scrollTo({
      left: container.scrollLeft + (targetRect.left + targetRect.width / 2) - (containerRect.left + containerRect.width / 2),
      behavior: "instant"
    })

    // Vertical scroll at page level
    const targetCenterY = targetRect.top + targetRect.height / 2
    const viewportCenterY = window.innerHeight / 2
    window.scrollBy({
      top: targetCenterY - viewportCenterY,
      behavior: "instant"
    })
  }, 50)
}
```

Key changes:
- Container `scrollTo` only sets `left` (no `top`)
- Vertical centering uses `window.scrollBy` instead of container scroll

**Step 2: Run tests**

Run: `mix test test/web/live/family_live/show_test.exs`
Expected: All tests pass (hook behavior isn't tested in LiveView tests, but DOM structure is intact).

**Step 3: Commit**

```
git add lib/web/live/family_live/show.html.heex
git commit -m "Update ScrollToFocus hook for horizontal-only container scroll"
```

---

### Task 5: Add layout guidelines to learnings

**Files:**
- Modify: `docs/learnings.md`

**Step 1: Append layout guidelines section**

Add the following to the end of `docs/learnings.md`:

```markdown
## Page layout should be full-width with scoped scroll containers

Pages should go edge-to-edge with no padding on `<main>`. Each page controls its own internal spacing. Horizontal scroll should only exist on specific content containers (e.g., a tree canvas), never on the full page — use `overflow-x-hidden` on the outer wrapper and `overflow-x-auto` on the scrollable container. Vertical scroll should be page-level (the browser's natural scroll behavior), not constrained to individual containers.

**Fix:** When adding a new page, do not add `overflow-y-auto` or `max-h-screen` to content containers. Let the page grow naturally. Only add `overflow-x-auto` to containers whose content may exceed the viewport width.
```

**Step 2: Commit**

```
git add docs/learnings.md
git commit -m "Add layout guidelines to learnings"
```

---

### Task 6: Run precommit and verify

**Step 1: Run precommit**

Run: `mix precommit`
Expected: Compilation clean (no warnings), formatting clean, all tests pass.

**Step 2: Fix any issues**

If precommit fails, fix the issues and re-run until clean.

**Step 3: Final commit (if any fixes needed)**

```
git add -A
git commit -m "Fix precommit issues"
```
