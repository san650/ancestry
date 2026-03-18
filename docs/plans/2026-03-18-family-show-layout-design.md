# Family Show Layout Design

## Goal

Restructure the Family Show page layout to: full-width edge-to-edge content, tree view with horizontal scroll only in its container, sidebar at fixed width on desktop and on top on mobile, vertical scroll for the entire page.

## Design Decisions

- **No `full_width` attr** — remove padding from `<main>` globally. All pages go edge-to-edge.
- **CSS grid** for the two-panel layout rather than flexbox.
- **Sidebar on top on mobile** via CSS `order` classes, not DOM reordering.
- **Horizontal scroll** constrained to tree canvas only; outer container gets `overflow-x-hidden`.
- **Vertical scroll** is page-level — no `overflow-y` on tree container.

## Changes

### 1. Layouts.app — Remove main padding

`<main>` becomes `<main class="min-h-100">` — no `px-*` or `pt-*`.

### 2. Family Show template — CSS grid layout

Replace `flex flex-col lg:flex-row` with:

```heex
<div class="grid grid-cols-1 lg:grid-cols-[1fr_18rem] overflow-x-hidden">
  <%!-- Sidebar: first on mobile, last on desktop --%>
  <div class="order-first lg:order-last border-b lg:border-b-0 lg:border-l border-base-200">
    <.live_component module={SidePanelComponent} ... />
  </div>

  <%!-- Tree Canvas: last on mobile, first on desktop --%>
  <div id="tree-canvas" class="overflow-x-auto p-6 order-last lg:order-first" phx-hook=".ScrollToFocus">
    ...tree content...
  </div>
</div>
```

- `grid-cols-[1fr_18rem]` on `lg:` — tree takes remaining space, sidebar fixed at 18rem (288px).
- `order-first`/`order-last` swaps visual order by breakpoint so sidebar appears on top on mobile.
- `overflow-x-hidden` on the grid prevents full-page horizontal scroll.
- `overflow-x-auto` on tree canvas enables horizontal scroll within it.

### 3. SidePanelComponent — Simplify classes

Remove width and border classes. Parent grid handles sizing and borders.

```elixir
# From:
"border-l border-base-200 bg-base-100 flex flex-col p-4 gap-6",
"w-72 lg:w-72",
"max-lg:w-full max-lg:border-l-0 max-lg:border-t"

# To:
"bg-base-100 flex flex-col p-4 gap-6"
```

### 4. ScrollToFocus hook — Horizontal only

Remove vertical scroll from the hook since vertical scrolling is now page-level. If vertical centering is needed, use `window.scrollTo` instead of container scroll.

### 5. Learnings

Document in `doc/learnings.md` that the general layout guidelines are:
- Full-width edge-to-edge pages, no padding on `<main>`
- Horizontal scroll only on specific containers, never the full page
- Vertical scroll on the whole page, not individual containers
