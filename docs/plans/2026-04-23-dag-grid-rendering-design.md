# DAG Grid Rendering Design

## Summary

Replace the current flexbox-based TreeView rendering with a CSS Grid-based DAG (Directed Acyclic Graph) rendering. Rename all "tree" terminology to "graph/DAG" to reflect the actual data structure. The new approach uses a grid matrix where each person occupies exactly one cell, with SVG connectors drawn by a JS hook.

## Motivation

The current rendering uses recursive flexbox layouts with JS-drawn SVG connectors. This creates several issues:
- Complex nested DOM structure makes debugging layout problems difficult
- Connector positioning depends on deeply nested element queries
- No clear separation between layout computation and rendering
- Width calculations are implicit (flexbox grows organically)

The grid approach makes layout explicit: Elixir computes `(col, row)` coordinates for every person, HEEx places them into CSS Grid cells, and JS draws connectors between known positions.

## Naming: Tree → Graph (DAG)

| Current | New |
|---------|-----|
| `PersonTree` | `PersonGraph` (already exists — keep) |
| `%PersonTree{}` | `%PersonGraph{}` |
| `tree` assign in LiveView | `graph` |
| `#tree-canvas` DOM ID | `#graph-canvas` |
| `TreeConnector` JS hook | `GraphConnector` |
| `family_subtree` component | `graph_node` component |
| `ancestor_subtree` component | `graph_generation` component |

## Data Structures

### PersonGraph (updated)

```elixir
%PersonGraph{
  focus_person: Person,
  family_id: integer,

  # Flat list of everything to render
  nodes: [GraphNode],     # all people + separators, with grid coords

  # Grid dimensions
  grid_cols: integer,     # total columns (MAX_WIDTH)
  grid_rows: integer,     # total rows (DEPTH)

  # Connections (for JS to draw SVG)
  edges: [GraphEdge]      # parent→child, couple links
}
```

### GraphNode

```elixir
%GraphNode{
  id: String.t(),          # unique within this graph
  type: :person | :separator,
  col: integer,            # 0-based column
  row: integer,            # 0-based row

  # Only for :person nodes
  person: Person | nil,
  focus: boolean,          # is focus person?
  duplicated: boolean,     # pedigree collapse / cross-gen stub?
  has_more_up: boolean,    # truncated ancestors?
  has_more_down: boolean   # truncated descendants?
}
```

### GraphEdge

```elixir
%GraphEdge{
  type: :parent_child | :current_partner | :previous_partner,
  relationship_kind: String.t(),  # "parent", "married", "relationship", "divorced", "separated"
  from_id: String.t(),            # source node id
  to_id: String.t()               # target node id
}
```

The `type` field is **structural** — it determines connector routing strategy:
- `:parent_child` → vertical routing between rows, uses layered mid-y lanes
- `:current_partner` → horizontal routing, positioned after the person
- `:previous_partner` → horizontal routing, positioned before the person (affects child group lane assignment)

The `relationship_kind` field is **visual** — it determines CSS styling (solid/dashed, color). It maps directly to the `type` field on `Ancestry.Relationships.Relationship` and is passed through as `data-relationship-kind` on SVG elements.

Edges are produced during Phase 1 (traversal): each parent-child relationship and each partner relationship encountered generates a `GraphEdge`. The `relationship_kind` is read from the existing `Relationship` schema's metadata.

### Separator Nodes

Separators are `%GraphNode{type: :separator}` — first-class entities in the DAG that serve three purposes:

1. **Centering padding** — make a group's width even so the couple above can center perfectly
2. **Group boundaries** — visual whitespace between children of different parents
3. **Width equalization** — narrower generations get extra separators to fill up to `grid_cols`

## Grid Placement Algorithm

### Input / Output

```
Input:  FamilyGraph (in-memory index) + focus_person_id + {ancestors, descendants, other}
Output: %PersonGraph{nodes, edges, grid_cols, grid_rows}
```

> **Migration note:** The current `%PersonGraph{}` struct has nested fields (`ancestors`, `center`, `descendants`) representing a recursive tree. The new struct replaces these with flat `nodes` and `edges` lists. All downstream consumers (LiveView templates, `person_card_component.ex`, tests) must be updated to work with the flat structure.

### Phase 1: Traverse & Assign Generations

Walk the graph from the focus person, applying depth limits:

1. Place `focus_person` at gen 0. Add to `visited = %{person_id => gen}`.
2. Walk UP through parent edges:
   - For each parent, assign `gen = child_gen + 1` (up to `ancestors` limit)
   - At each ancestor level, expand lateral children (up to `others` depth)
   - Lateral descendants bounded by the `descendants` setting (relative to focus)
3. Walk DOWN through child edges:
   - For each child, assign `gen = parent_gen - 1` (down to `descendants` limit)
   - Group children by partner
4. Apply duplication rules at each encounter (see [Duplication Rules](#duplication-rules))
5. Mark `has_more_up` / `has_more_down` at depth boundaries

### Phase 2: Group Into Family Units

Organize entries by generation. Within each generation, cluster people into **family units** — a set of siblings (children of the same couple) plus their partners and ex-partners.

Within each family unit, order:
```
[ex-partners...] [person] [current-partner] | [next sibling by birth_date] [their partners]
```

Add separators between family units.

### Phase 3: Order Family Units Across Generations

Family units at gen N must be ordered to match the column ordering of their parent couple at gen N+1. This is the key invariant that prevents connector crossings.

For the widest generation: order family units left-to-right (primary: parent couple position, secondary: birth_date).

For each generation above/below: propagate outward from the widest generation. When going UP, order parent couples to match their children's column range below. When going DOWN, order children to match their parent couple's column position above. In case of conflict (a family unit has connections to both the row above AND below), the connection to the adjacent already-placed row takes priority.

### Phase 4: Count Cells and Find Grid Dimensions

For each generation:
- `width = sum(family_unit widths + separator counts)`
- Pad odd-width child groups to even when their parents are a couple (2 cells need even-width below for centering). Single parents with odd children don't need padding.

```
grid_cols = max(width across all generations)
grid_rows = max_gen - min_gen + 1
```

For narrower generations: add equalizing separators to reach `grid_cols`.

### Phase 5: Assign Column Positions

Start from the widest generation, assign `col = 0, 1, 2, ...` left-to-right.

For each adjacent generation: center each family unit under/above its parent couple's column range. Add centering separators between and around units.

## Duplication Rules

### Couples Are Always Horizontal

Partners must be adjacent on the same row. Couple connectors are always horizontal — never vertical. When partners are at different natural generations (generational crossing), the higher-generation partner is duplicated at the lower generation row.

### Dup People Don't Represent Their Natural Generation

Duplicated stubs exist as visual partner markers at the needed row, not at the person's natural generational level.

### Three Rules for Encounters

When a person is encountered a second time during traversal:

1. **Same gen + compatible position → reuse.** One cell serves multiple roles (child of GP + parent of grandchild). No dup needed. A position is "compatible" when the person's existing cell can serve the new role **without requiring them to be adjacent to a new partner they're not already next to.** Concretely: reuse when (a) the person is at the correct generation, AND (b) any new connections (parent→child edges) can be drawn from the existing cell without crossing other connectors. Example: Brother in Type 4, who is both GP's child (connected up) and Niece's parent with Wife (connected down), all at gen 2 in the same family group.

2. **Same gen + incompatible position → dup.** Person is already placed at the correct generation but in a different family group — they can't be moved adjacent to their partner without breaking sibling order or crossing connectors. Example: Bro-Y and Sis-Y in Type 3, who are laterals in separate family groups (under GPA and GPB respectively) but need to form a couple for Parent-2.

3. **Different gen → always dup.** Partner stub placed at the needed generation row. Example: Uncle in Type 4, natural gen 2 but needed at gen 1 to sit next to Niece.

### "Other" Configuration

> **Note:** The existing `PersonGraph` uses `other` (singular) in `@default_opts`. This spec uses the existing field name.

The `other` setting controls lateral expansion:

- `other = N` where `N > 0`
- Walk N ancestor levels up from the focus person
- From those ancestors, include every descendant
- Descendants are bounded by the `descendants` setting, which is **relative to the focus person** (not to the lateral ancestor)

## Cycle Type Resolution

All 5 cycle types from the CLAUDE.md are handled by the grid algorithm. The refined duplication rules produce smaller grids than the previous "always stub" approach.

| Type | Scenario | Grid | Dups | Resolution |
|------|----------|------|------|------------|
| 1 | Cousins marry | 5×4 | 0 | GP+GM once, C and D reused as siblings (same gen) |
| 2 | Woman + 2 brothers | 3×3 | 0 | Bro-1 reused: same gen, adjacent as ex-partner |
| 3 | Double first cousins | 6×4 | 2 | Bro-Y + Sis-Y dup'd (same gen but incompatible positions) |
| 4 | Uncle + niece | 3×4 | 1 | Uncle dup'd at gen 1 (cross-gen couple), Brother reused |
| 5 | Siblings + same family | 4×3 | 0 | No duplication, partner edges invisible |

### Type 4 Detail (Generational Crossing)

```
Gen 3: Grandpa, Grandma
Gen 2: Uncle, Brother, Wife         ← Uncle & Brother as siblings (same row)
Gen 1: Uncle(dup), Niece             ← Uncle dup'd to sit next to his partner
Gen 0: Focus
```

- Uncle(dup) at gen 1 is a visual partner marker, not representing Uncle's natural generation
- Brother at gen 2 serves dual role (GP's child + Niece's parent) from one cell
- All couples horizontal, all parent→child connectors span exactly 1 row

## Rendering Architecture

### Data Flow

```
FamilyGraph (2 DB queries) → PersonGraph (DAG + grid coords) → HEEx (CSS Grid cells) → JS + SVG (connectors only)
```

Elixir computes everything: the PersonGraph builder produces a flat list of `GraphNode`s with `(col, row)` coordinates and a list of `GraphEdge`s. HEEx iterates the nodes, placing each in its grid cell. JS reads edges from a `data-edges` JSON attribute and draws SVG connectors.

### HEEx Template Structure

```heex
<div id="graph-canvas" phx-hook="GraphConnector"
     data-edges={Jason.encode!(@graph.edges)}
     class="relative overflow-auto">
  <div style={"display: grid; grid-template-columns: repeat(#{@graph.grid_cols}, var(--cell-width)); grid-template-rows: repeat(#{@graph.grid_rows}, var(--cell-height)); gap: var(--cell-gap);"}>
    <%= for node <- @graph.nodes do %>
      <div style={"grid-column: #{node.col + 1}; grid-row: #{node.row + 1};"}
           data-node-id={node.id}
           data-focus={node.focus}>
        <%= case node.type do %>
          <% :person -> %> <.person_card node={node} ... />
          <% :separator -> %> <!-- empty cell, dotted border for debug -->
        <% end %>
      </div>
    <% end %>
  </div>
  <!-- SVG overlay inserted by JS hook -->
</div>
```

### CSS Grid Properties

- Each cell occupies exactly one grid position (`grid-column: N; grid-row: M`)
- Partners are in two contiguous cells, visually glued with CSS to appear as one unit
- Separators render as empty cells with subtle dotted borders (for debugging)
- Grid gap provides uniform spacing between cells

## Connector Drawing (JS + SVG)

### SVG Overlay

An absolutely-positioned SVG element covers the entire grid container. `pointer-events: none` ensures clicks pass through to person cards. The JS hook (`GraphConnector`) manages the SVG lifecycle.

### Three Connector Types

1. **Parent → Child (single):** Orthogonal path from couple center bottom → vertical to mid-gap → horizontal to child center x → vertical to child top.

2. **Branch (couple → N children):** Couple center → vertical to mid-gap → horizontal bar spanning all children → vertical drops to each child.

3. **Couple link:** Horizontal line between adjacent cells. Solid for current partners, dashed for ex/previous partners.

### Layered Routing (Avoiding Overlap)

When multiple child groups exist in the same row gap (couple children + solo children from each parent + ex-partner children), each group routes at a different vertical lane:

Each child group (couple children, solo children of left parent, solo children of right parent, ex-partner children) routes at a different vertical lane in the row gap. Lane count adapts dynamically: `lane_step = gap_height / (group_count + 1)`. Each group's horizontal segments are at different y-coordinates, preventing visual merging. Solo connector origins are offset from the parent center to avoid overlapping with couple branch drops at the same x-coordinate.

### Styling via data-relationship-kind

Each SVG connector element gets a `data-relationship-kind` attribute matching the `GraphEdge.relationship_kind`. CSS rules handle visual differentiation:

| relationship_kind | Visual |
|-------------------|--------|
| `"parent"` | Solid gray, 1.5px |
| `"married"` | Solid green, 2px |
| `"relationship"` | Solid green, 2px |
| `"divorced"` | Dashed red, 1.5px |
| `"separated"` | Dashed red, 1.5px |

New relationship types automatically get the attribute — add CSS rules without touching JS.

### Redraw Triggers

- `mounted()` — initial draw after DOM ready
- `updated()` — LiveView re-renders (focus change, depth change)
- `ResizeObserver` — window/container resize

On each redraw: clear SVG children, re-query all cell rects via `getBoundingClientRect`, redraw all connectors.

## UX Details

### Focus Person

- Highlighted with CSS (accent border, slight scale or glow)
- Not necessarily centered in the grid — positioned at its natural `(col, row)`
- Scrolled into view on mount and after updates: `scrollIntoView({ behavior: "smooth", block: "center", inline: "center" })`
- Debounced 50ms to avoid scrolling during rapid patches

### "Has More" Indicators

Rendered in HEEx (not JS) as small icons positioned within the person card cell:
- `has_more_up`: up-arrow icon at the top of the cell (truncated ancestors beyond depth limit)
- `has_more_down`: down-arrow icon at the bottom of the cell (truncated descendants beyond depth limit)

These are part of the person card component, not separate grid cells or SVG elements. They don't affect grid dimensions.

### Debug Grid

Show subtle dotted borders on all cells (including separators) for layout debugging. Controlled by a CSS class or debug flag.

### Person Cards

Each person cell renders a card showing:
- Name and photo (or placeholder)
- Birth/death years
- Gender-coded top border (blue, pink, neutral)
- Click target: name/photo re-centers the graph (changes focus person)
- Navigation icon: goes to person detail page
- Duplicated indicator: "(duplicated)" label + reduced opacity for dup stubs
