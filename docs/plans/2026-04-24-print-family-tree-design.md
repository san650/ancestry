# Print Family Tree — Design Spec (v3: Indented List)

**Date:** 2026-04-24
**Status:** Approved

## Goal

Replace the grid-based print page with an indented list layout that always fits on paper regardless of family size. The print page opens in a new tab, shows the family name and an indented hierarchy of people with their relationships, and auto-triggers the browser print dialog.

## Why not the CSS grid approach?

The grid-based print view (v1: `@media print`, v2: dedicated page with grid) failed because:
- Wide trees (15+ columns at 120px) overflow any print page
- CSS `zoom` creates coordinate mismatches between `scrollWidth` (unzoomed) and `getBoundingClientRect` (zoomed), breaking SVG connector positioning
- Dynamic column widths make text unreadable for wide trees
- SVG connectors are inherently coupled to the grid layout and break when the layout changes between screen and print

An indented list is pure HTML text — no SVG, no fixed-width grid, no coordinate system. It wraps naturally within any page width.

## Layout

### Structure

```
Family Name
(centered on Focus Person)

ANCESTORS
Person (year)
    | relationship Partner (year)
        Person (year)
            | relationship Partner (year)
                Sibling 1 (year)
                Sibling 2 (year)
                ★ Focus Person (year)        ← highlighted
                    | relationship Partner (year)
                        DESCENDANTS
                        Child 1 (year)
                        Child 2 (year)
                Sibling 3 (year)

Other Ancestor Branch (year)
    | relationship Partner (year)
        → Person (see above)                 ← back-reference
```

### Rules

1. **Direct descendant first.** The person who belongs to the lineage is the top-level entry. Partners are always indented below on a separate line.

2. **Partners on separate lines.** Always shown as indented sub-entries with the relationship type label: `| casado con Partner`, `| divorciado de Partner`, etc.

3. **Multiple partners are sequential sub-blocks.** Each partnership gets its own indented block under the person. Children of each partnership are nested under their respective partner line.

4. **Solo children.** Children with no known co-parent are listed under a "sin pareja conocida" (no known partner) label.

5. **Focus person highlighted.** Light blue background with a left blue border. Name in bold blue.

6. **Duplicates become back-references.** Instead of showing a person twice, the second occurrence is an italic arrow reference: `→ Person (see above)` or on the partner line: `← son of X (above)`.

7. **Gender indicator.** Small colored square: blue (male), pink (female). Prints well in color, degrades to dark/light in B&W.

8. **Life span.** Birth year shown after name. If deceased: `(1920–1988)`. If living: `(1982)`.

9. **Ancestors/Descendants labels.** Section headers in small uppercase text with a thin bottom border.

10. **Vertical border lines.** Left border on indented blocks shows the parent-child relationship visually.

## Data source

The indented list renders from the same `PersonGraph` struct used by the interactive tree view. The `PersonGraph` provides:
- `nodes` — all people in the tree with their generation, focus flag, and duplicate flag
- `edges` — parent-child and partner relationships with types

However, the indented list does NOT use the grid coordinate system (col/row) or the SVG edges. Instead, it walks the `FamilyGraph` directly, starting from the oldest ancestors and recursing downward, which naturally produces the indented hierarchy.

## Files changed

### Modified files
1. **`lib/web/live/family_live/print.ex`** — Rewrite `handle_params` to build an indented tree data structure from `FamilyGraph` instead of `PersonGraph`
2. **`lib/web/live/family_live/print.html.heex`** — Replace `print_graph_canvas` with a recursive indented list template
3. **`lib/web/live/family_live/print_graph_component.ex`** — Replace grid rendering with indented list rendering (rename to `print_tree_component.ex`)
4. **`lib/web/live/family_live/CLAUDE.md`** — Update to reflect indented list approach

### Removed
- `GraphConnector` JS hook is no longer used by the print page
- `AutoPrint` hook remains (still triggers `window.print()`)
- `@page` CSS rule remains (landscape, small margins)

### Unchanged
- Route (`/org/:org_id/families/:family_id/print`)
- "Print tree" button in family show page (meatball menu + nav drawer)
- `Layouts.print` layout function
- `AutoPrint` JS hook

## Out of scope

- PDF export
- Photo inclusion
- Custom paper size selection
- Printing the grid view (abandoned due to SVG/layout issues)
