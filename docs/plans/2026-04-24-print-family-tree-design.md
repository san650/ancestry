# Print Family Tree — Design Spec (v2)

**Date:** 2026-04-24
**Status:** Approved

## Goal

Add a dedicated print page for the family tree. A "Print" button on the family show page opens a new tab with a clean, print-optimized layout showing only the family name and text-only person cards with SVG connectors. The page auto-triggers the browser's print dialog.

## Why not `@media print`?

The first approach (CSS `@media print` on the existing page) failed because:
- Nested scroll containers (`#tree-canvas` + `#graph-canvas`) clip the wide tree grid
- SVG connectors are drawn for screen layout coordinates and don't redraw for print reflow
- Fixed inline grid columns (`repeat(N, 120px)`) overflow any print page width
- `beforeprint`/`afterprint` timing prevents reliable scaling

A dedicated page avoids all of these: the `GraphConnector` hook draws SVG for the actual rendered layout (which IS the print layout), and there are no scroll containers to fight.

## Architecture

**Route:** `/org/:org_id/families/:family_id/print`

Query params (carried from the family show page):
- `person` — focus person ID
- `ancestors`, `descendants`, `other` — depth settings
- `display` — `partial` or `complete`

**LiveView:** `Web.FamilyLive.Print` — minimal mount, loads family + graph, renders.

**Layout:** A new `print` layout function in `Web.Layouts` — just the page title, CSS, JS assets. No header, no toolbar, no nav drawer.

**Component:** `Web.FamilyLive.PrintGraphComponent` — a separate graph component for print with its own simplified person card.

## Components

### Shared with family show

| Component | What it provides |
|---|---|
| `PersonGraph.build/3` | Graph computation (nodes, edges, grid dimensions) |
| `FamilyGraph.from/3` | Family data indexing |
| `GraphConnector` JS hook | SVG connector drawing |

### New for print

| Component | Purpose |
|---|---|
| `Web.FamilyLive.Print` | LiveView — loads data, renders print page |
| `Web.FamilyLive.PrintGraphComponent` | Print-specific graph canvas + person cards |
| `Layouts.print/1` | Minimal layout — no chrome |

### Print graph component

`PrintGraphComponent` renders:
- The outer `#graph-canvas` div with the `GraphConnector` hook (same as screen, but with `overflow: visible` instead of `overflow: auto`)
- The CSS grid with the same column/row structure
- Simplified person cards: a bordered box with just the person's name, no photos, no hover, no navigation

The grid structure (column count, row positioning, edges JSON) comes from the same `PersonGraph` struct, ensuring layout parity with the screen view.

### Print person card

A `<div>` (not a `<button>`) with:
- Border (solid, light gray)
- Gender border-top color (blue/pink/gray)
- Person's display name, centered
- Fixed width matching the grid column (120px)
- No photos, no hover effects, no focus styles, no navigation links, no "has more" pills

## Print trigger

A "Print tree" item in the family show page's:
- **Desktop:** meatball menu (right side of toolbar)
- **Mobile:** nav drawer page actions

The link opens the print page in a new tab (`target="_blank"`). It carries the current tree state via query params (focus person, depth settings, display mode).

## Auto-print on load

A small JS hook (`AutoPrint`) on the print page that calls `window.print()` after the `GraphConnector` hook has finished drawing. This can be a `setTimeout` after mount to ensure the SVG is rendered.

## Files

### New files
1. `lib/web/live/family_live/print.ex` — Print LiveView
2. `lib/web/live/family_live/print.html.heex` — Print template
3. `lib/web/live/family_live/print_graph_component.ex` — Print graph canvas + person card

### Modified files
4. `lib/web/components/layouts.ex` — Add `print/1` layout function
5. `lib/web/live/family_live/show.html.heex` — Add "Print tree" to meatball menu + nav drawer
6. `lib/web/router.ex` — Add print route
7. `assets/js/app.js` — Register `AutoPrint` hook
8. `lib/web/live/family_live/CLAUDE.md` — Document print page relationship

## Out of scope

- PDF export
- Photo inclusion toggle
- Custom paper size selection
- Print preview within the app
