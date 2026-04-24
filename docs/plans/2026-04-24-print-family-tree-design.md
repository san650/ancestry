# Print Family Tree — Design Spec

**Date:** 2026-04-24
**Status:** Approved

## Goal

Add a print-friendly view for the family tree page (`FamilyLive.Show`). When a user prints the page (Cmd+P / Ctrl+P), only the family name and the tree grid with text-only person cards should appear — all application chrome is hidden.

## Approach

Pure CSS `@media print` rules in `app.css`. No new routes, no new LiveViews, no JS changes.

## What gets hidden

| Element | Reason |
|---|---|
| App header (logo, nav links, account info) | Chrome |
| Toolbar (breadcrumb actions, hamburger, edit/delete/meatball) | Chrome |
| Side panel (desktop metrics, vaults, galleries, people list) | Chrome |
| Nav drawer (mobile) | Chrome |
| Tree drawer (depth controls, both mobile and desktop) | Chrome |
| "Has more" chevron pills (ancestor/descendant indicators) | Interactive-only |
| Person navigation arrows (overlaid link on hover) | Interactive-only |
| Photos (all person card images and placeholder icons) | User preference — text-only print |
| Modals (edit, delete, galleries, search, etc.) | Chrome |
| Flash messages | Chrome |

## What gets shown and restyled

### Family name heading

A print-only `<h1>` placed above the tree canvas in `show.html.heex`. Hidden on screen (`hidden print:block`), visible only when printing. Sources the family name from `@family.name`.

### Person cards

Each card becomes a compact text-only box:
- **Name** — always visible, centered
- **Life span dates** — shown if present (e.g. "1940–2015")
- **Gender border-top** — retained (blue for male, pink for female, gray for unknown). Degrades gracefully to grayscale in B&W printing
- **No photos** — images and placeholder icon divs hidden
- **No interactive affordances** — no hover effects, no focus ring, no navigation overlay

### Tree grid

- Remains as a CSS grid (same columns and rows)
- `overflow: auto` removed — let content flow naturally for print
- `hide-scrollbar` class ineffective in print (no scrollbars anyway)
- Background forced to white

### SVG connectors

Kept as-is. The relationship lines drawn by the `GraphConnector` JS hook are lightweight SVG paths that print natively. They are essential for reading the tree structure.

### Page orientation

`@page { size: landscape }` hint — trees are typically wider than tall.

## Print trigger

No new UI button. Users use the browser's native Cmd+P / Ctrl+P. The `@media print` rules activate automatically.

## Files changed

1. **`assets/css/app.css`** — Add `@media print` block with hide/show/restyle rules
2. **`lib/web/live/family_live/show.html.heex`** — Add print-only `<h1>` with family name above tree canvas
3. **`lib/web/live/family_live/CLAUDE.md`** — Document that the family show page is print-friendly; new features must include `print:hidden` or equivalent to avoid appearing in print output unless explicitly intended for print

## Out of scope

- Print button in the UI (Cmd+P is sufficient)
- Photo inclusion toggle
- Dedicated print route/LiveView
- PDF export
