# SVG Path Connectors for TreeView

Replace the current multi-`<line>` SVG connector system with single `<path>` elements drawn by a unified `TreeConnector` JS hook. This reduces DOM element count, enables semantic grouping, and solves horizontal bar overlap issues when multiple relationship groups share a connector area.

## Decisions

- **Unified SVG overlay**: One absolute-positioned SVG covers the entire tree canvas. All connections (couple links, branch connectors, ancestor connectors) are drawn as `<path>` elements in this single SVG.
- **One hook**: A single `TreeConnector` hook replaces `BranchConnector`, `AncestorConnector`, and all inline SVGs in `couple_card`.
- **Fixed Y-offset per group**: Each relationship group gets its horizontal bar at `barY = base + (groupIndex × 10px)`. The last vertical segment (bar → children) is shorter for later groups since the bar is already closer.
- **No data attributes on paths**: Paths carry no `data-` attributes. Connection topology is derived from DOM positions of person cards (which already have `data-person-id`).
- **No `phx-update="ignore"` on tree canvas**: The hook re-injects and redraws its SVG on every `updated()` call, allowing LiveView to patch the tree HTML freely.

## Architecture

### SVG Overlay

A single `<svg>` element injected by the `TreeConnector` hook inside `#tree-canvas`. Styled with `position: absolute; inset: 0; pointer-events: none;` and sized to match the container's scroll dimensions. All `<path>` elements live here.

### TreeConnector Hook

**File**: `assets/js/tree_connector.js`

**Lifecycle**:
- `mounted()` — initial draw + `ResizeObserver` on the tree container
- `updated()` — full redraw
- `destroyed()` — disconnect `ResizeObserver`
- All draws wrapped in `requestAnimationFrame`

**DOM traversal**:
1. Find subtree roots via `[data-primary-column]`
2. For each root, find couple card (`[data-couple-card]`) and children row (`[data-children-row]`)
3. For each couple card, find person cards and ex/previous partner elements
4. For ancestor connections, find `[data-ancestor-parents-row]` and `[data-ancestor-parent-column]`
5. Measure positions with `getBoundingClientRect()` relative to the SVG, offset by `scrollLeft`/`scrollTop`

**Draw cycle**:
1. Clear SVG via `svg.replaceChildren()`
2. Resize SVG to container scroll dimensions
3. Walk DOM, collect connection groups
4. For each group, build path `d` string and create `<path>` element
5. Append all paths

### Path Construction

**Branch connector** (couple → children): Given origin `(ox, oy)` and N child targets `(cx_i, cy_i)`:

```
M ox,oy V barY H cx_1 V cy_1 M ox,barY H cx_2 V cy_2 ...
```

One `<path>` per group. Produces T-shape (1 child) or comb-shape (N children).

**Couple-level connections** (partner/ex-partner links): Horizontal paths at the couple card's vertical midpoint. Dashed stroke for ex-partners.

**Ancestor connectors** (parents → couple below): Same pattern mirrored vertically. One path per parent-child connection. No Y-offset needed (always one-to-one).

### Y-Offset Stacking Order

Groups are stacked top-to-bottom in the connector zone:

1. **Partner children** — `barY = base` (closest to parents)
2. **Previous partners' children** — `barY = base + offset`
3. **Ex-partners' children** — `barY = base + 2×offset`
4. **Solo children** — `barY = base + N×offset` (furthest from parents)

Offset: 10px. Connector zone height: `base(20px) + (numGroups × 10px)`.

| Scenario | Groups | Height | Extra vs today |
|---|---|---|---|
| Single couple, shared children | 1 | 20px | +0px |
| Couple + previous partner | 2 | 30px | +10px |
| Couple + ex + previous | 3 | 40px | +20px |
| Couple + 2 ex + prev + solo | 5 | 60px | +40px |

### Styling

- Stroke color: `rgba(128,128,128,0.2)` (unchanged)
- Stroke width: 3px
- Ex-partner paths: `stroke-dasharray="6,4"`
- All other paths: solid
- SVG overlay: `pointer-events: none`

## Template Changes

### `person_card_component.ex`

- **`couple_card/1`**: Remove all inline `<svg>` elements (ex-partner and previous-partner separator SVGs). Person cards and wrapping structure stay.
- **`subtree_children/1`**: Remove the connector `<div>` with `phx-hook="BranchConnector"` and its inner `<svg>`. Children row (`[data-children-row]`) stays.
- **`ancestor_subtree/1`**: Remove the connector `<div>` with `phx-hook="AncestorConnector"` and its inner `<svg>`. Ancestor parents row stays.
- **`vline/1`**: Keep as-is. Used only for placeholder connectors (add-parent, add-child).

### `show.html.heex`

- Add `phx-hook="TreeConnector"` to the `#tree-canvas` div.
- Remove the `vline` between ancestors and center row (line 87) — TreeConnector handles that connection.

### `app.js`

- Remove `BranchConnector`, `AncestorConnector`, `makeSvgLine`, `CONNECTOR_STROKE`
- Import and register `TreeConnector` from `./tree_connector.js`

## Edge Cases

- **Empty tree**: Hook finds no person cards, draws nothing.
- **Single person, no relationships**: No connections to draw. Placeholder cards use static `vline`.
- **Deeply nested subtrees**: Single SVG overlay covers all depths — no per-level hooks needed.
- **LiveView patches**: `updated()` triggers full SVG redraw. No `phx-update="ignore"` on the tree canvas.
- **Resize**: `ResizeObserver` triggers redraw to keep SVG in sync.

## Testing

**LiveView tests verify DOM structure**:
- `#tree-canvas` has `phx-hook="TreeConnector"`
- Couple cards retain `data-couple-card`, `data-person-a-id`, `data-person-b-id`
- Child columns retain `data-child-column`, `data-child-person-id`, `data-line-origin`
- Ancestor columns retain `data-ancestor-parent-column`, `data-target-person-id`
- No inline SVGs inside couple cards
- No `BranchConnector` or `AncestorConnector` hook references

**Manual/e2e verification**:
- Connectors render between couple and children
- Dashed lines for ex-partner groups
- Ancestor connectors render above focus couple
- Connectors update on focus person change
- Connectors redraw on window resize
- No regressions with placeholder `vline` connectors

**Not tested**: SVG path `d` values or exact connector heights (layout-dependent implementation details).

Existing user flow tests in `test/user_flows/` should pass unchanged.
