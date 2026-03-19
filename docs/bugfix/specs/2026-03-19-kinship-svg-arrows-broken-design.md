# Kinship SVG Arrows Broken

## Problem

The SVG arrow connectors added in commit `4fce85a` have three visual bugs:

1. **Arrows invisible** — `arrow_connector` component uses `text-base-200` (matches background color). Design doc specifies `text-base-300`. This affects all arrow usages: direct-line paths, branch connectors, and within-branch arrows.
2. **Horizontal line looks wrong** — CSS `border-t-2` creates a full-width horizontal rule between MRCA and branches. Looks like a random divider instead of a tree fork.
3. **Cluttered connector section** — Two separate arrow divs plus the horizontal bar between MRCA and branches create a messy visual hierarchy.

## Fix

### 1. Fix arrow color

In the `arrow_connector` private function component in `kinship_live.ex`, change `text-base-200` to `text-base-300`. This single change fixes the color for all call sites (direct-line, branch connectors, and within-branch arrows).

### 2. Replace connector section with SVG fork

Remove the connector section between the MRCA node and the two-column branch layout — from `<%!-- Branch connectors --%>` through the closing `</div>` of the horizontal connector bar. This includes:
- The two `arrow_connector` wrapper divs
- The horizontal connector bar div

Replace with a single `<.fork_connector />` call. The `fork_connector` is a private function component (`defp fork_connector(assigns)`) defined in `kinship_live.ex` alongside `arrow_connector`. It renders an SVG inverted-Y shape:
- Vertical line from center top going down
- Two lines splitting left and right toward the branch column centers
- Uses `text-base-300` stroke color
- SVG uses `viewBox` and spans the full container width, ~40px tall
- `stroke-linecap: round`, `stroke-linejoin: round` to match existing arrow style

Visual result:
```
      MRCA
        │
   ┌────┴────┐
   │          │
Branch A  Branch B
```

## Arrow direction note

Both branches render top-to-bottom (MRCA at top, persons at bottom), so all visual arrows correctly point down. The original design doc's mention of "UP" for the left branch referred to the logical traversal direction (ascending to ancestor), not the visual rendering direction.

## Files to modify

- `lib/web/live/kinship_live.ex` — fix `text-base-200` → `text-base-300` in `arrow_connector`, add `fork_connector` private function component
- `lib/web/live/kinship_live.html.heex` — replace the branch connectors + horizontal bar section with `<.fork_connector />`
