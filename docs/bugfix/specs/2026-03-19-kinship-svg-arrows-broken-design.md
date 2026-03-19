# Kinship SVG Arrows Broken

## Problem

The SVG arrow connectors added in commit `4fce85a` have three visual bugs:

1. **Arrows invisible** — `arrow_connector` uses `text-base-200` (matches background). Design doc specifies `text-base-300`.
2. **Horizontal line looks wrong** — CSS `border-t-2` creates a full-width horizontal rule between MRCA and branches. Looks like a random divider instead of a tree fork.
3. **Cluttered connector section** — Two separate arrow divs plus the horizontal bar between MRCA and branches create a messy visual hierarchy.

## Fix

### 1. Fix arrow color

In `arrow_connector` component (`kinship_live.ex`), change `text-base-200` to `text-base-300`.

### 2. Replace connector section with SVG fork

Remove the three divs between the MRCA node and the two branches (lines 178-191 in template):
- The two `arrow_connector` divs (branch connectors)
- The horizontal connector bar

Replace with a single `fork_connector` function component that renders an SVG inverted-Y shape:
- Vertical line from center top going down
- Two lines splitting left and right to the edges
- Uses `text-base-300` stroke color
- SVG spans full container width, ~40px tall
- `stroke-linecap: round`, `stroke-linejoin: round` to match existing arrow style

Visual result:
```
      MRCA
        │
   ┌────┴────┐
   │          │
Branch A  Branch B
```

## Files to modify

- `lib/web/live/kinship_live.ex` — fix arrow color, add `fork_connector` component
- `lib/web/live/kinship_live.html.heex` — replace connector section with `<.fork_connector />`
