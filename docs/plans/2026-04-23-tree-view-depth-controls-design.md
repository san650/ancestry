# Tree View Depth Controls — Design Spec

**Date:** 2026-04-23
**Status:** Approved
**Feature:** Configurable drawer panel for controlling tree view depth (ancestors, descendants, other/laterals)

---

## Summary

Add a UI for controlling how many generations of ancestors, descendants, and lateral relatives (siblings, cousins) the tree view displays. Desktop uses a collapsible bottom drawer; mobile uses a header button that opens a bottom sheet modal. Settings persist in URL params and socket assigns. The backend already accepts depth options — this feature adds the UI and implements the currently-unused "other" (lateral) traversal.

---

## Current State

- `PersonGraph.build/3` accepts `ancestors:`, `descendants:`, and `other:` options
- Default: `ancestors: 2, descendants: 2, other: 1`
- These defaults are hardcoded — no UI to change them
- The `other` parameter is accepted but **has no implementation** — laterals are never traversed
- "Has more" chevrons appear at depth boundaries but are informational only

---

## URL Schema

```
/org/:org_id/families/:family_id?person=123&ancestors=5&descendants=3&other=2&display=complete
```

- Only non-default values appear in the URL (keeps URLs clean)
- Defaults: `ancestors=2`, `descendants=2`, `other=1`, `display=partial`
- `display=complete` sets all depths to 20 and hides sliders
- `display=partial` (or absent) uses individual depth values
- All values are integers, clamped to `0..20` in `handle_params`

---

## Data Flow

```
User drags slider
  -> phx-change event with new value
  -> handle_event patches URL: ?person=X&ancestors=5&descendants=2&other=1
  -> handle_params reads params, stores in assigns (@ancestors, @descendants, @other, @display)
  -> PersonGraph.build(focus, family_graph, ancestors: 5, descendants: 2, other: 1)
  -> Graph re-renders
  -> GraphConnector hook redraws SVG + requestAnimationFrame scroll to focus person
```

Changes are **live** — the tree rebuilds immediately as the user adjusts sliders. The graph rebuild uses the cached `FamilyGraph` (zero DB queries), so it's fast even for large families.

**Important:** All code paths that patch the URL with a `person` param must carry forward the current depth assigns (`@ancestors`, `@descendants`, `@other`, `@display`). This includes:
- The `"focus_person"` event handler (re-centers tree on a clicked person)
- The `refresh_graph` helper (called after relationship saves, CSV imports, etc.)
- The person selector dropdown

---

## UI Components

### Desktop: Bottom Drawer

- **Visibility:** `hidden lg:block` — desktop only
- **Collapsed (default):** Thin bar at bottom of tree view area showing current settings summary: "Partial Tree | Parents 2 | Children 2 | Other 0" with a chevron-up icon
- **Expanded:** Panel slides up, showing controls in a horizontal row:
  - Display mode toggle: "Partial Tree" / "Complete Tree" (segmented control)
  - Three range sliders: Parents (0–20), Children (0–20), Other (0–20)
  - Each slider shows label + current value badge
- **Open/close:** JS-only CSS class toggle (no server roundtrip for cosmetic animation)
- **When `display=complete`:** Sliders are hidden, replaced with "Showing all generations"

### Mobile: Header Button + Bottom Sheet

- **Visibility:** `lg:hidden` — mobile only
- **Trigger:** "Tree" button with bar-chart icon in the header bar
- **Bottom sheet modal:** Slides up over the tree (tree dims behind with backdrop)
  - Drag handle at top
  - "Tree View" title + "Done" button
  - Display mode toggle (same as desktop)
  - Three range sliders (vertical layout, same as desktop but stacked)
  - Close via "Done" button or swipe down
- **Separate markup from desktop drawer** — avoids `playwright-dual-responsive-layout` issues

### Sliders

- Native `<input type="range" min="0" max="20" step="1">` with `phx-change` and `phx-debounce="200"` to avoid rapid-fire rebuilds during drag
- Label + value badge showing current generation count
- Values sent as strings from DOM — `String.to_integer/1` in handler (per `js-hook-native-types` learning)
- The "Other" slider's `max` is dynamically clamped to the current `@ancestors` value — prevents confusing mismatches where the slider shows 5 but only 2 levels of laterals appear

### Display Mode Toggle

- "Partial Tree": use individual slider values (default)
- "Complete Tree": set all depths to 20, hide sliders
- Switching back to "Partial Tree" restores previous slider values (stored in `@partial_settings` assign). If no previous values exist (e.g., user lands directly on `?display=complete`), restores to defaults `{ancestors: 2, descendants: 2, other: 1}`
- Toggle uses `phx-click` to patch URL, not a checkbox in a `phx-change` form (avoids `checkbox-server-state-revert` issues)

---

## Backend: "Other" (Lateral) Implementation

### Semantics

From the graph CLAUDE.md:

> **Other:** How many ancestor levels up to walk, then expand all descendants from those ancestors. 0 = direct line only, 1 = siblings, 2 = cousins.

### Constraint

Same-level people only show if their common ancestor is already included in the ancestors list. The effective other depth is `min(other, ancestors)`.

| ancestors | other | What shows |
|-----------|-------|------------|
| 2 | 0 | Direct line only (current behavior) |
| 2 | 1 | Siblings (parents' other children) |
| 2 | 2 | Siblings + cousins (grandparents' other descendants) |
| 1 | 3 | Only siblings — cousins need grandparents but ancestors=1 stops at parents |
| 3 | 2 | Siblings + cousins (grandparents are visible at ancestors=3) |

### Algorithm

Added to `person_graph.ex` after the existing ancestor/descendant traversal:

1. For each ancestor at generation `g` (where `g <= min(other, ancestors)`), find their children not already in the graph
2. Add those children at generation `g - 1` (correct generational level)
3. For each newly added person, traverse their descendants downward. Stop when `child_generation < -max_descendants` (where focus person is generation 0, children are -1, grandchildren are -2, etc.). This bounds all lateral descendants to the same floor as direct-line descendants
4. Apply existing duplication rules for any re-encounters
5. Per `at-limit-simplified-path-data-loss` learning: query **all partner types** at boundaries, not just active partners

---

## Edge Cases

### Performance
- `FamilyGraph` is built once at mount (2 DB queries). All depth changes use the cached graph — zero additional queries
- Even at `other=20, ancestors=20`, traversal is bounded by actual family data
- Large families with "Complete Tree" may produce wide grids — handled by existing horizontal scrolling

### Slider Edge Cases
- `ancestors=0`: only focus person's row and below; `other` is effectively 0 (no ancestors to branch from)
- `descendants=0`: only focus person's row and above
- All set to 0: just the focus person alone

### GraphConnector Hook
- Already handles variable graph sizes — redraws SVG on every `updated()` callback
- Already uses `requestAnimationFrame` for scroll-to-focus (per `hook-mounted-scroll-timing` learning)
- No changes needed to the JS hook

### Lateral "Has More" Indicators
- Lateral persons added by the "other" traversal may themselves have truncated descendants
- These laterals show `has_more_down` indicators using the same logic as direct-line persons

### Drawer Hook
- Small JS hook for desktop drawer open/close CSS toggle
- `destroyed()` must guard against unmounted state (per `hook-destroyed-must-guard-state` learning)

### Gettext
- Slider labels need `gettext` calls + Spanish translations: "Parents", "Children", "Other", "Partial Tree", "Complete Tree", "Showing all generations", "Tree View", "Done"

---

## Files to Modify

| File | Change |
|------|--------|
| `lib/web/live/family_live/show.ex` | Read depth params in `handle_params`, add `handle_event` for slider changes, add depth assigns, update `focus_person` event and `refresh_graph` helper to preserve depth params |
| `lib/web/live/family_live/show.html.heex` | Add desktop drawer markup, mobile header button + bottom sheet |
| `lib/web/live/family_live/graph_component.ex` | No changes expected — receives `@graph` which already adapts to depth |
| `lib/ancestry/people/person_graph.ex` | Implement "other" traversal after ancestor/descendant phases |
| `assets/js/app.js` | Register new drawer hook |
| `assets/js/tree_drawer.js` | New file — JS hook for drawer open/close toggle |
| `assets/css/app.css` | Drawer and bottom sheet styles |
| `priv/gettext/es-UY/LC_MESSAGES/default.po` | Spanish translations for new UI strings |
| `test/user_flows/` | E2E tests for drawer interaction, depth changes, mobile sheet |

---

## Decisions Log

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Desktop UI | Bottom drawer | Non-intrusive, shows summary when collapsed |
| Mobile UI | Header button + bottom sheet | Familiar mobile pattern, doesn't overlap tree content |
| Persistence | URL params + socket assigns | Shareable, survives refresh, idiomatic LiveView |
| Update mode | Live (immediate) | Graph rebuild is in-memory (0 queries), fast enough for real-time |
| Max generations | 20 | Practical upper bound for genealogy |
| Drawer open/close | JS-only | Cosmetic toggle doesn't need server roundtrip |
| Desktop/mobile markup | Separate blocks | Avoids playwright-dual-responsive-layout issues |
| Complete Tree behavior | Hides sliders, sets all to 20 | Clear visual distinction from partial mode |
