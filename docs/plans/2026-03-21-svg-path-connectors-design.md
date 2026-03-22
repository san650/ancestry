# SVG Path Connectors for TreeView

Replace the current multi-`<line>` SVG connector system with single `<path>` elements drawn by a unified `TreeConnector` JS hook. This reduces DOM element count, enables semantic grouping, and solves horizontal bar overlap issues when multiple relationship groups share a connector area.

## Decisions

- **Unified SVG overlay**: One absolute-positioned SVG covers the entire tree canvas. All connections (couple links, branch connectors, ancestor connectors) are drawn as `<path>` elements in this single SVG.
- **One hook**: A single `TreeConnector` hook replaces `BranchConnector`, `AncestorConnector`, and all inline SVGs in `couple_card`. It also absorbs the `ScrollToFocus` logic since `#tree-canvas` can only have one `phx-hook`.
- **Fixed Y-offset per group**: Each relationship group gets its horizontal bar at a stacked Y level. The last vertical segment (bar → children) is shorter for later groups since the bar is already closer.
- **No data attributes on paths**: Paths carry no `data-` attributes. Connection topology is derived from DOM positions of person cards (which already have `data-person-id`).
- **No `phx-update="ignore"` on tree canvas**: The hook re-injects and redraws its SVG on every `updated()` call, allowing LiveView to patch the tree HTML freely.
- **Visual change**: Y-offset stacking is new behavior compared to the current implementation (which draws all groups at the same barY, only offsetting ex-partner dashed lines by 8px). This is an intentional improvement.
- **No horizontal line between main couple**: The main couple (person_a + person_b) does NOT get a horizontal connecting line — they are adjacent cards within the couple card background. Only ex-partner and previous-partner separators get horizontal lines, matching current behavior.
- **Standardize dash pattern**: All ex-partner dashed lines use `stroke-dasharray="6,4"` (the current BranchConnector value). The couple-card inline SVGs currently use `"5"` — this minor difference is intentionally normalized.

## Architecture

### SVG Overlay

A single `<svg>` element injected by the `TreeConnector` hook inside `#tree-canvas`. The SVG has a stable `id="tree-connector-svg"` so that LiveView's morphdom preserves it across patches rather than removing it as an unexpected node. Styled with `position: absolute; inset: 0; pointer-events: none;` and sized to match the container's scroll dimensions. No `viewBox` attribute — the SVG uses CSS pixel coordinates directly. All `<path>` elements have `fill="none"`.

The `#tree-canvas` container must have `position: relative` (Tailwind: `relative`) added to establish the positioning context for the absolute SVG overlay.

### TreeConnector Hook

**File**: `assets/js/tree_connector.js`

This hook merges the responsibilities of the current `BranchConnector`, `AncestorConnector`, `ScrollToFocus`, and inline couple-card SVGs into a single hook.

**Lifecycle**:
- `mounted()` — inject SVG overlay (with `id="tree-connector-svg"`), initial draw, set up `ResizeObserver` on `this.el` (the `#tree-canvas` div), register `scroll_to_focus` event handler
- `updated()` — full redraw (fires on every LiveView patch, including non-tree patches like modal opens — the redraw is cheap since it's a single `requestAnimationFrame` pass)
- `destroyed()` — disconnect `ResizeObserver`, remove injected SVG. `handleEvent` listeners are automatically cleaned up by LiveView.

All draws wrapped in `requestAnimationFrame`.

**ScrollToFocus** (absorbed from the current `ScrollToFocus` hook):
- On `mounted()`, listen for `"scroll_to_focus"` push event via `this.handleEvent`
- On mount and on event, find `#focus-person-card` and call `scrollIntoView({ behavior: "smooth", block: "center", inline: "center" })` after a 50ms delay. The delay exists to let the DOM settle after a LiveView patch before measuring scroll position.

**DOM traversal**:
1. Find subtree roots via `[data-primary-column]`
2. For each root, find couple card (`[data-couple-card]`) and children row (`[data-children-row]`)
3. For each couple card, find person cards via `[data-person-id]` and separator spacers via `[data-ex-separator]` / `[data-previous-separator]`
4. For ancestor connections, find `[data-ancestor-parents-row]` and `[data-ancestor-parent-column]`
5. Measure positions with `getBoundingClientRect()` using the scroll-corrected formula (see below)

**Coordinate conversion**: All element positions are converted to SVG-local coordinates using:
```
svgX = elementRect.left - containerRect.left + container.scrollLeft
svgY = elementRect.top - containerRect.top + container.scrollTop
```
Where `containerRect` is `this.el.getBoundingClientRect()` and `container` is `this.el`.

**Draw cycle**:
1. Clear SVG via `svg.replaceChildren()`
2. Resize SVG to `this.el.scrollWidth` × `this.el.scrollHeight`
3. Walk DOM, collect connection groups
4. For each group, build path `d` string and create `<path>` element with `fill="none"`
5. Append all paths

### Path Construction

**Branch connector** (couple → children): The origin Y (`oy`) is the bottom edge of the couple card. The children target Y (`cy`) is the top edge of the child card. The `barY` for each group is:

```
barY = oy + 10 + (groupIndex × 10)
```

Where `groupIndex` starts at 0 for the first group. Given origin X (`ox`, the horizontal center of the connection origin) and N child target X positions (`cx_i`, the horizontal center of each child card):

```
M ox,oy V barY H cx_1 V cy M ox,barY H cx_2 V cy ...
```

One `<path>` per group. Produces T-shape (1 child) or comb-shape (N children).

**Couple-level connections** (ex-partner and previous-partner horizontal links): The couple card's DOM children appear in this order (left to right): `[ex_person_2, ex_separator_2, ex_person_1, ex_separator_1, prev_person_1, prev_separator_1, ..., person_a, person_b]`. The hook traverses the couple card's direct children and pairs each separator spacer with its adjacent person card (the person card immediately to its left). For each pair:

- Compute the horizontal midpoint between the person card's right edge and the main couple's left person card's left edge (i.e., the center of the separator spacer).
- Draw a horizontal path at the couple card's vertical midpoint, from the ex/previous person card center to the nearest main couple person card center.
- If the separator has children (indicated by the presence of child columns with matching `data-line-origin`), draw a vertical drop from the separator midpoint down. This vertical drop connects to the branch connector bar below.
- Ex-partner horizontal lines use dashed stroke; previous-partner lines use solid stroke.

**Ancestor connectors** (parents above → couple below): Given parent couple center `(px, py)` at the bottom of the parent couple card and child target `(cx, cy)` at the top of a person in the couple below, the `barY` is the vertical midpoint between the two:

```
barY = py + (cy - py) / 2
```

Path:
```
M px,py V barY H cx V cy
```

One path per parent-child connection. No Y-offset needed (always one-to-one). When there are two parent couples connecting to two different people in the child couple, two separate paths are drawn, each connecting a parent couple center to its respective child person center.

### Y-Offset Stacking Order

Groups are stacked top-to-bottom in the connector zone:

1. **Partner children** — `groupIndex = 0` (closest to parents)
2. **Previous partners' children** — `groupIndex = 1` (or 1..N for multiple previous partners)
3. **Ex-partners' children** — `groupIndex` continues (dashed lines)
4. **Solo children** — last `groupIndex` (furthest from parents)

Offset: 10px per group. The connector zone gap between couple card bottom and children row top must accommodate all groups. The hook dynamically sets the gap by applying an inline `margin-top` style on the children row element (`[data-children-row]`), computed as `max(20, 10 + numGroups × 10)` px. This replaces the old fixed 20px connector div.

| Scenario | Groups | Gap | Extra vs today |
|---|---|---|---|
| Single couple, shared children | 1 | 20px | +0px |
| Couple + previous partner | 2 | 30px | +10px |
| Couple + ex + previous | 3 | 40px | +20px |
| Couple + 2 ex + prev + solo | 5 | 60px | +40px |

### Styling

- Stroke color: `rgba(128,128,128,0.2)` (unchanged)
- Stroke width: 3px
- Stroke line join: `round` (for clean corners at path turns)
- Stroke line cap: `round`
- Fill: `none` (on every `<path>` element)
- Ex-partner paths: `stroke-dasharray="6,4"` (standardized from the current mix of `"5"` and `"6,4"`)
- All other paths: solid
- SVG overlay: `pointer-events: none`

## Template Changes

### `person_card_component.ex`

- **`couple_card/1`**: Remove all inline `<svg>` elements (ex-partner and previous-partner separator SVGs). Replace them with non-SVG spacer `<div>` elements that retain the `data-ex-separator` / `data-previous-separator` attributes. These spacers serve as positional anchors for the TreeConnector hook to compute origin-X for each group. Style them with a fixed width (`w-[40px]`, matching the current 40px SVG width) and the couple card's height.
- **`subtree_children/1`**: Remove the connector `<div>` with `phx-hook="BranchConnector"` and its inner `<svg>`. Children row (`[data-children-row]`) stays. Remove the old fixed 20px height — the TreeConnector hook will set `margin-top` dynamically on the children row based on the number of groups.
- **`ancestor_subtree/1`**: Remove the connector `<div>` with `phx-hook="AncestorConnector"` and its inner `<svg>`. Ancestor parents row stays. Add a CSS gap of 20px between ancestor parents and the couple card below (fixed, since ancestor connectors have no Y-offset stacking).
- **`vline/1`**: Keep as-is. Used only for placeholder connectors (add-parent, add-child).

### `show.html.heex`

- Add `phx-hook="TreeConnector"` to the `#tree-canvas` div (replacing the current `phx-hook="ScrollToFocus"`).
- Add `relative` to the `#tree-canvas` class list (for absolute SVG positioning context).
- Remove the `vline` between ancestors and center row (line 87) — TreeConnector handles that connection.

### `app.js`

- Remove `BranchConnector`, `AncestorConnector`, `ScrollToFocus`, `makeSvgLine`, `CONNECTOR_STROKE`
- Import and register `TreeConnector` from `./tree_connector.js`

## Edge Cases

- **Empty tree / no tree (`@tree == nil`)**: The `#tree-canvas` div shows an empty state or person selector instead of the tree. The hook finds no person cards or couple cards and draws nothing. The SVG overlay is empty.
- **Single person, no relationships**: No connections to draw. Placeholder cards use static `vline`.
- **Deeply nested subtrees**: Single SVG overlay covers all depths — no per-level hooks needed.
- **LiveView patches (non-tree)**: `updated()` fires on every patch, including modal opens. The SVG has a stable `id="tree-connector-svg"` so morphdom preserves it. The redraw clears and rebuilds its content within a single `requestAnimationFrame` — no visual flicker.
- **Resize**: `ResizeObserver` on `this.el` triggers redraw to keep SVG in sync with container size changes.
- **Scroll**: The coordinate conversion formula accounts for `scrollLeft`/`scrollTop`, so connections align correctly even when the tree is scrolled.
- **Couple with no children but with ex-partners**: The hook draws only the horizontal couple-level connections. No branch connector paths are needed.

## Testing

**LiveView tests verify DOM structure**:
- `#tree-canvas` has `phx-hook="TreeConnector"`
- Couple cards retain `data-couple-card`, `data-person-a-id`, `data-person-b-id`
- Child columns retain `data-child-column`, `data-child-person-id`, `data-line-origin`
- Ancestor columns retain `data-ancestor-parent-column`, `data-target-person-id`
- Separator spacers retain `data-ex-separator` / `data-previous-separator` (now on `<div>` elements instead of `<svg>`)
- No inline SVGs inside couple cards
- No `BranchConnector`, `AncestorConnector`, or `ScrollToFocus` hook references in templates

**Existing tests to update**:
- `test/web/live/family_live/tree_multiple_partners_test.exs` — assertions on `[data-previous-separator]` and `[data-ex-separator]` should still pass since the attributes are preserved on the replacement spacer divs. Verify after implementation.

**Manual/e2e verification**:
- Connectors render between couple and children
- Dashed lines for ex-partner groups
- Horizontal links between ex-partners and previous partners in couple cards
- Ancestor connectors render above focus couple
- Connectors update on focus person change
- Scroll-to-focus behavior works on mount and focus change
- Connectors redraw on window resize
- No regressions with placeholder `vline` connectors
- Dynamic gap between couple and children grows correctly with multiple groups

**Not tested**: SVG path `d` values or exact connector heights (layout-dependent implementation details).

Existing user flow tests in `test/user_flows/` should pass unchanged.
