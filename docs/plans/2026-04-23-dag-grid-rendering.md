# DAG Grid Rendering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flexbox-based recursive TreeView with a CSS Grid-based DAG renderer where Elixir computes all grid coordinates and JS only draws SVG connectors.

**Architecture:** PersonGraph produces a flat list of GraphNodes (with col/row coordinates) and GraphEdges. HEEx iterates nodes into a CSS Grid. A JS hook reads edges as JSON and draws SVG connectors. See `docs/plans/2026-04-23-dag-grid-rendering-design.md` for the full design spec.

**Tech Stack:** Elixir/Phoenix LiveView, CSS Grid, SVG, JavaScript hooks

**Key references:**
- Design spec: `docs/plans/2026-04-23-dag-grid-rendering-design.md`
- Business logic: `lib/ancestry/people/CLAUDE.md`
- Learnings: `docs/learnings.jsonl` (grep for `morphdom`, `hook`, `svg`, `dom-patch`)
- E2E conventions: `test/user_flows/CLAUDE.md`

---

## File Structure

### New Files
| File | Responsibility |
|------|---------------|
| `lib/ancestry/people/graph_node.ex` | GraphNode struct |
| `lib/ancestry/people/graph_edge.ex` | GraphEdge struct (JSON-encodable for JS) |
| `lib/web/live/family_live/graph_component.ex` | Grid layout + person card rendering |
| `assets/js/graph_connector.js` | SVG connector drawing hook |
| `test/ancestry/people/graph_node_test.exs` | GraphNode tests |
| `test/ancestry/people/graph_edge_test.exs` | GraphEdge tests |

### Modified Files
| File | What Changes |
|------|-------------|
| `lib/ancestry/people/person_graph.ex` | Struct fields → flat nodes/edges. Algorithm → 5-phase grid placement. |
| `lib/web/live/family_live/show.ex` | `tree` assign → `graph`. Template calls updated. |
| `lib/web/live/family_live/show.html.heex` | Tree canvas → CSS Grid canvas with graph components. |
| `assets/js/app.js` | Register `GraphConnector`, remove `TreeConnector`. |
| `assets/css/app.css` | Add graph grid debug styles. |
| `test/ancestry/people/person_graph_test.exs` | Rewrite for flat struct assertions. |
| `test/web/live/family_live/show_test.exs` | Update tree → graph assertions. |

### Files to Remove (after migration)
| File | Replaced By |
|------|------------|
| `lib/web/live/family_live/person_card_component.ex` | `graph_component.ex` |
| `assets/js/tree_connector.js` | `graph_connector.js` |

---

## Task 1: Create GraphNode and GraphEdge Structs

**Files:**
- Create: `lib/ancestry/people/graph_node.ex`
- Create: `lib/ancestry/people/graph_edge.ex`
- Create: `test/ancestry/people/graph_node_test.exs`
- Create: `test/ancestry/people/graph_edge_test.exs`

- [ ] **Step 1: Write GraphNode test**

```elixir
# test/ancestry/people/graph_node_test.exs
defmodule Ancestry.People.GraphNodeTest do
  use ExUnit.Case, async: true

  alias Ancestry.People.GraphNode

  describe "struct" do
    test "creates a person node with all fields" do
      node = %GraphNode{
        id: "person-42",
        type: :person,
        col: 2,
        row: 1,
        person: %{id: 42, first_name: "Alice"},
        focus: true,
        duplicated: false,
        has_more_up: false,
        has_more_down: true
      }

      assert node.id == "person-42"
      assert node.type == :person
      assert node.col == 2
      assert node.row == 1
      assert node.focus == true
      assert node.has_more_down == true
    end

    test "creates a separator node" do
      node = %GraphNode{
        id: "sep-0-3",
        type: :separator,
        col: 0,
        row: 3
      }

      assert node.type == :separator
      assert node.person == nil
    end

    test "defaults boolean fields to false" do
      node = %GraphNode{id: "p-1", type: :person, col: 0, row: 0}

      assert node.focus == false
      assert node.duplicated == false
      assert node.has_more_up == false
      assert node.has_more_down == false
    end
  end
end
```

- [ ] **Step 2: Run test — verify it fails**

Run: `mix test test/ancestry/people/graph_node_test.exs`
Expected: Compilation error — `Ancestry.People.GraphNode` not found.

- [ ] **Step 3: Implement GraphNode**

```elixir
# lib/ancestry/people/graph_node.ex
defmodule Ancestry.People.GraphNode do
  @moduledoc """
  A cell in the DAG grid — either a person or a separator.

  Person nodes carry the person struct and metadata (focus, duplicated, has_more).
  Separator nodes are empty cells for centering, group boundaries, or width equalization.
  """

  defstruct [
    :id,
    :type,
    :col,
    :row,
    :person,
    focus: false,
    duplicated: false,
    has_more_up: false,
    has_more_down: false
  ]
end
```

- [ ] **Step 4: Run test — verify it passes**

Run: `mix test test/ancestry/people/graph_node_test.exs`
Expected: 3 tests, 0 failures.

- [ ] **Step 5: Write GraphEdge test**

```elixir
# test/ancestry/people/graph_edge_test.exs
defmodule Ancestry.People.GraphEdgeTest do
  use ExUnit.Case, async: true

  alias Ancestry.People.GraphEdge

  describe "struct" do
    test "creates a parent_child edge" do
      edge = %GraphEdge{
        type: :parent_child,
        relationship_kind: "parent",
        from_id: "person-1",
        to_id: "person-2"
      }

      assert edge.type == :parent_child
      assert edge.relationship_kind == "parent"
    end

    test "creates a current_partner edge" do
      edge = %GraphEdge{
        type: :current_partner,
        relationship_kind: "married",
        from_id: "person-1",
        to_id: "person-2"
      }

      assert edge.type == :current_partner
    end
  end

  describe "JSON encoding" do
    test "encodes to JSON for data-edges attribute" do
      edge = %GraphEdge{
        type: :parent_child,
        relationship_kind: "parent",
        from_id: "person-1",
        to_id: "person-2"
      }

      {:ok, json} = Jason.encode(edge)
      decoded = Jason.decode!(json)

      assert decoded["type"] == "parent_child"
      assert decoded["relationship_kind"] == "parent"
      assert decoded["from_id"] == "person-1"
      assert decoded["to_id"] == "person-2"
    end
  end
end
```

- [ ] **Step 6: Run test — verify it fails**

Run: `mix test test/ancestry/people/graph_edge_test.exs`
Expected: Compilation error — `Ancestry.People.GraphEdge` not found.

- [ ] **Step 7: Implement GraphEdge**

```elixir
# lib/ancestry/people/graph_edge.ex
defmodule Ancestry.People.GraphEdge do
  @moduledoc """
  A connection between two GraphNodes in the DAG.

  `type` is structural (determines connector routing):
  - `:parent_child` — vertical routing between rows
  - `:current_partner` — horizontal routing, after the person
  - `:previous_partner` — horizontal routing, before the person

  `relationship_kind` is visual (determines CSS styling):
  maps to `Ancestry.Relationships.Relationship` type field.
  """

  @derive Jason.Encoder

  defstruct [
    :type,
    :relationship_kind,
    :from_id,
    :to_id
  ]
end
```

- [ ] **Step 8: Run all tests — verify they pass**

Run: `mix test test/ancestry/people/graph_node_test.exs test/ancestry/people/graph_edge_test.exs`
Expected: All pass.

- [ ] **Step 9: Commit**

```
git add lib/ancestry/people/graph_node.ex lib/ancestry/people/graph_edge.ex \
       test/ancestry/people/graph_node_test.exs test/ancestry/people/graph_edge_test.exs
git commit -m "Add GraphNode and GraphEdge structs for DAG grid rendering"
```

---

## Task 2: Rewrite PersonGraph Struct and Traversal

**Files:**
- Modify: `lib/ancestry/people/person_graph.ex`
- Modify: `test/ancestry/people/person_graph_test.exs`

This task changes the PersonGraph struct from nested trees to flat lists and implements Phase 1 (traverse & assign generations) and Phase 2 (group into family units). The existing traversal logic is adapted, not rewritten from scratch.

- [ ] **Step 1: Write tests for the new struct and basic traversal**

Update `test/ancestry/people/person_graph_test.exs` — replace nested struct assertions with flat node/edge assertions. Start with the simplest case: focus person alone.

> **Note:** The existing `build/3` signature is `build(%Person{}, graph_or_id, opts)` — Person first, then FamilyGraph. Keep this signature; update tests to match.

The existing tests use a `family_with_tree` setup that creates a family with people and relationships. Adapt it to return the FamilyGraph and Person structs needed. Check `test/ancestry/people/person_graph_test.exs` for the existing setup and adapt it.

```elixir
# In person_graph_test.exs, replace existing tests with:
describe "build/3 — simple family" do
  setup [:family_with_tree]

  test "returns flat nodes with grid coordinates", %{focus: focus, family_graph: fg} do
    graph = PersonGraph.build(focus, fg)

    assert %PersonGraph{nodes: nodes, edges: edges, grid_cols: cols, grid_rows: rows} = graph
    assert is_list(nodes)
    assert is_list(edges)
    assert cols > 0
    assert rows > 0

    # Focus person exists in nodes
    focus_node = Enum.find(nodes, &(&1.focus == true))
    assert focus_node != nil
    assert focus_node.person.id == focus.id
    assert focus_node.type == :person
  end

  test "focus person has correct generation (row)", %{focus: focus, family_graph: fg} do
    graph = PersonGraph.build(focus, fg)
    focus_node = Enum.find(graph.nodes, &(&1.focus == true))

    # Focus row should be valid within grid bounds
    assert focus_node.row >= 0
    assert focus_node.row <= graph.grid_rows - 1
  end

  test "parents appear one row above focus", %{focus: focus, father: father, mother: mother, family_graph: fg} do
    graph = PersonGraph.build(focus, fg, ancestors: 1, descendants: 0, other: 0)
    focus_node = Enum.find(graph.nodes, &(&1.focus == true))

    parent_nodes = Enum.filter(graph.nodes, fn n ->
      n.type == :person and n.row == focus_node.row - 1
    end)

    parent_ids = Enum.map(parent_nodes, & &1.person.id)
    assert father.id in parent_ids
    assert mother.id in parent_ids
  end

  test "generates parent_child edges", %{focus: focus, family_graph: fg} do
    graph = PersonGraph.build(focus, fg, ancestors: 1, descendants: 0, other: 0)

    parent_child_edges = Enum.filter(graph.edges, &(&1.type == :parent_child))
    assert length(parent_child_edges) > 0
  end

  test "generates couple edges for partners", %{focus: focus, family_graph: fg} do
    graph = PersonGraph.build(focus, fg, ancestors: 1, descendants: 0, other: 0)

    couple_edges = Enum.filter(graph.edges, &(&1.type == :current_partner))
    # Parents should have a couple edge
    assert length(couple_edges) >= 1
  end
end
```

- [ ] **Step 2: Run tests — verify they fail**

Run: `mix test test/ancestry/people/person_graph_test.exs`
Expected: Failures — PersonGraph struct doesn't have `nodes`/`edges`/`grid_cols`/`grid_rows` fields.

- [ ] **Step 3: Update PersonGraph struct**

In `lib/ancestry/people/person_graph.ex`, change the struct definition:

```elixir
defstruct [
  :focus_person,
  :family_id,
  nodes: [],
  edges: [],
  grid_cols: 0,
  grid_rows: 0
]
```

Remove the old fields: `ancestors`, `center`, `descendants`. The `generations` map is used internally during traversal but not stored in the final struct.

- [ ] **Step 4: Implement the build/3 pipeline**

Rewrite `build/3` as a pipeline. Adapt existing traversal functions (`build_ancestor_tree`, `build_family_unit_full`, etc.) into the new phases. This is the largest code change — refer to the design spec Section "Grid Placement Algorithm" for the 5-phase approach.

Key implementation notes:
- Phase 1: Adapt existing `build_ancestor_tree/5` and `build_child_units_acc/5` to produce flat entries with generation numbers instead of nested tree nodes
- Apply the refined duplication rules (same-gen reuse, same-gen incompatible dup, different-gen always dup) — see `lib/ancestry/people/CLAUDE.md` Duplication Rules section
- Track visited persons with `%{person_id => generation}` map
- Mark `has_more_up`/`has_more_down` at depth boundaries
- At boundaries, still query ALL partner types (not just active) — per learning `at-limit-simplified-path-data-loss`

- [ ] **Step 5: Run tests iteratively until passing**

Run: `mix test test/ancestry/people/person_graph_test.exs`
Fix issues iteratively. The simple family tests should pass before moving on.

- [ ] **Step 6: Commit**

```
git commit -m "Rewrite PersonGraph struct and traversal for flat grid layout"
```

---

## Task 3: Implement Grid Placement and Edge Generation

**Files:**
- Modify: `lib/ancestry/people/person_graph.ex`
- Modify: `test/ancestry/people/person_graph_test.exs`

This task implements Phases 3-5 (ordering, grid dimensions, column positions) and edge generation. It also adds tests for all 5 cycle types.

- [ ] **Step 1: Write cycle type tests**

Add tests for each cycle type to `person_graph_test.exs`. These tests create specific family structures and verify the grid output. Each test should:
- Create the family with the appropriate relationships
- Build the PersonGraph
- Assert grid dimensions
- Assert dup counts
- Assert no connector crossings (check that parent-child edges don't share horizontal segments)

Each cycle type test needs a helper that creates the family structure using `People.create_person/2` and `Relationships.create_relationship/3`. Use the existing test helpers in `test/support/` — check `fixtures.ex` and `factory.ex` for available helpers.

The test structure for each cycle type follows this pattern:

```elixir
describe "cycle types" do
  test "Type 1: cousins who marry — no duplication" do
    # Setup: Create org, family, and people with relationships:
    # GP+GM → C, D (parent rels). C+WifeC (married). D+WifeD (married).
    # C+WifeC → E (parent). D+WifeD → F (parent). E+F (married). E+F → Focus (parent).
    # Build FamilyGraph, then PersonGraph with ancestors: 3
    #
    # Assertions:
    # - 0 nodes with duplicated: true
    # - GP and GM person IDs each appear exactly once in nodes
    # - grid dimensions match expected (5 cols × 4 rows)
  end

  test "Type 2: woman marries two brothers — Brother-1 reused" do
    # Setup: GP+GM → B1, B2. B1+Mom (divorced). B2+Mom (married).
    # B1+Mom → Half. B2+Mom → Focus.
    # Build with ancestors: 2, descendants: 1
    #
    # Assertions:
    # - 0 nodes with duplicated: true
    # - B1's person_id appears exactly once in nodes
    # - grid dimensions: 3 cols × 3 rows
  end

  test "Type 3: double first cousins — Bro-Y and Sis-Y dup'd" do
    # Setup: GPA+GMA → BX, BY. GPB+GMB → SX, SY.
    # BX+SX (married). BY+SY (married).
    # BX+SX → P1. BY+SY → P2. P1+P2 (married). P1+P2 → Focus.
    # Build with ancestors: 3, other: 1
    #
    # Assertions:
    # - exactly 2 nodes with duplicated: true
    # - GPA, GMA, GPB, GMB each appear once (not duplicated)
    # - grid dimensions: 6 cols × 4 rows
  end

  test "Type 4: uncle marries niece — Uncle dup'd, Brother reused" do
    # Setup: GP+GM → Uncle, Brother. Brother+Wife (married).
    # Brother+Wife → Niece. Uncle+Niece (married). Uncle+Niece → Focus.
    # Build with ancestors: 3, other: 1
    #
    # Assertions:
    # - exactly 1 node with duplicated: true (Uncle's dup)
    # - Uncle appears in 2 nodes (one original at gen 2, one dup at gen 1)
    # - Brother appears in exactly 1 node (gen 2, NOT duplicated)
    # - grid dimensions: 3 cols × 4 rows
    # - Uncle dup's row < Uncle original's row (dup at lower gen)
  end

  test "Type 5: siblings marry into same family — no duplication" do
    # Setup: GPA+GMA → BX, BY. GPB+GMB → SX, SY.
    # BX+SX (married). BY+SY (married).
    # BX+SX → Focus. BY+SY → Cousin.
    # Build with ancestors: 2, other: 1
    #
    # Assertions:
    # - 0 nodes with duplicated: true
    # - grid dimensions: 4 cols × 3 rows
  end
end
```

> **Note:** The exact person creation and relationship setup code depends on the existing test helpers. Read `test/support/fixtures.ex` and `test/ancestry/people/person_graph_test.exs` for the current patterns before writing these tests.

- [ ] **Step 2: Run tests — verify they fail**

Run: `mix test test/ancestry/people/person_graph_test.exs`
Expected: Failures — grid dimensions wrong, cycle handling not implemented.

- [ ] **Step 3: Implement Phase 3 — order family units**

Within each generation, order family units to match the column ordering of their parent couples in the adjacent generation. This prevents connector crossings.

- [ ] **Step 4: Implement Phase 4 — count cells and grid dimensions**

Count cells per generation (people + separators). Pad odd-width child groups to even when parents are a couple. Find MAX_WIDTH. Compute grid_rows.

- [ ] **Step 5: Implement Phase 5 — assign column positions**

Start from widest generation, assign columns left-to-right. Center each family unit under/above its parent couple. Add equalizing separators.

- [ ] **Step 6: Implement edge generation**

Walk all relationships in the traversal output. For each parent-child pair and each partner pair, create a GraphEdge with the appropriate type and relationship_kind (read from the existing Relationship metadata).

- [ ] **Step 7: Run all cycle type tests — iterate until passing**

Run: `mix test test/ancestry/people/person_graph_test.exs`
All cycle type tests should pass.

- [ ] **Step 8: Commit**

```
git commit -m "Implement grid placement algorithm and cycle type handling"
```

---

## Task 4: Create GraphConnector JS Hook

**Files:**
- Create: `assets/js/graph_connector.js`
- Modify: `assets/js/app.js`

- [ ] **Step 1: Create the GraphConnector hook**

```javascript
// assets/js/graph_connector.js

// Learning: safe-dom-in-hooks — use createElementNS, not innerHTML
// Learning: hook-destroyed-must-guard-state — guard destroyed() callback

const SVG_NS = "http://www.w3.org/2000/svg"

export const GraphConnector = {
  mounted() {
    this._container = this.el.querySelector("[data-graph-grid]")
    if (!this._container) return

    this._svg = document.createElementNS(SVG_NS, "svg")
    this._svg.style.cssText = "position:absolute;top:0;left:0;width:100%;height:100%;pointer-events:none;overflow:visible;"
    this.el.appendChild(this._svg)

    this._observer = new ResizeObserver(() => this._draw())
    this._observer.observe(this._container)

    this._draw()
    this._scrollToFocus()
  },

  updated() {
    this._draw()
    this._scrollToFocus()
  },

  destroyed() {
    // Learning: hook-destroyed-must-guard-state
    if (!this._observer) return
    this._observer.disconnect()
  },

  _draw() {
    if (!this._svg || !this._container) return

    // Learning: safe-dom-in-hooks — use replaceChildren to clear
    this._svg.replaceChildren()

    const edgesAttr = this.el.dataset.edges
    if (!edgesAttr) return

    const edges = JSON.parse(edgesAttr)
    const containerRect = this.el.getBoundingClientRect()

    // Group edges by type
    const coupleEdges = edges.filter(e => e.type === "current_partner" || e.type === "previous_partner")
    const parentChildEdges = edges.filter(e => e.type === "parent_child")

    // Draw couple connectors (horizontal)
    coupleEdges.forEach(edge => this._drawCoupleEdge(edge, containerRect))

    // Group parent-child edges by parent pair for branch rendering
    const branches = this._groupIntoBranches(parentChildEdges)
    branches.forEach(branch => this._drawBranch(branch, containerRect))
  },

  _drawCoupleEdge(edge, containerRect) {
    const fromEl = this._container.querySelector(`[data-node-id="${edge.from_id}"]`)
    const toEl = this._container.querySelector(`[data-node-id="${edge.to_id}"]`)
    if (!fromEl || !toEl) return

    const fromRect = this._toLocal(fromEl.getBoundingClientRect(), containerRect)
    const toRect = this._toLocal(toEl.getBoundingClientRect(), containerRect)

    // Horizontal line between adjacent cells
    const y = fromRect.top + fromRect.height / 2
    const x1 = Math.min(fromRect.right, toRect.right)
    const x2 = Math.max(fromRect.left, toRect.left)

    const line = document.createElementNS(SVG_NS, "line")
    line.setAttribute("x1", Math.min(x1, x2))
    line.setAttribute("y1", y)
    line.setAttribute("x2", Math.max(x1, x2))
    line.setAttribute("y2", y)
    line.setAttribute("data-relationship-kind", edge.relationship_kind || "")

    // Style based on type
    if (edge.type === "previous_partner") {
      line.setAttribute("stroke", "rgba(248,113,113,0.6)")
      line.setAttribute("stroke-width", "2")
      line.setAttribute("stroke-dasharray", "6")
    } else {
      line.setAttribute("stroke", "rgba(74,222,128,0.6)")
      line.setAttribute("stroke-width", "2")
    }

    this._svg.appendChild(line)
  },

  _groupIntoBranches(edges) {
    // Group by the row gap they cross (parent row → child row)
    // and by the parent couple (edges sharing from_id pattern)
    // Returns arrays of edges that share the same parent pair
    const groups = {}
    edges.forEach(edge => {
      const fromEl = this._container.querySelector(`[data-node-id="${edge.from_id}"]`)
      if (!fromEl) return
      const key = edge.from_id
      if (!groups[key]) groups[key] = []
      groups[key].push(edge)
    })
    return Object.values(groups)
  },

  _drawBranch(edges, containerRect) {
    if (edges.length === 0) return

    const fromEl = this._container.querySelector(`[data-node-id="${edges[0].from_id}"]`)
    if (!fromEl) return
    const fromRect = this._toLocal(fromEl.getBoundingClientRect(), containerRect)

    const childRects = edges.map(edge => {
      const toEl = this._container.querySelector(`[data-node-id="${edge.to_id}"]`)
      if (!toEl) return null
      return this._toLocal(toEl.getBoundingClientRect(), containerRect)
    }).filter(Boolean)

    if (childRects.length === 0) return

    const originX = fromRect.left + fromRect.width / 2
    const originY = fromRect.bottom
    const midY = originY + (childRects[0].top - originY) / 2

    // Vertical from parent to mid
    this._makeLine(originX, originY, originX, midY)

    if (childRects.length === 1) {
      // Single child — route to child
      const childX = childRects[0].left + childRects[0].width / 2
      const childY = childRects[0].top
      this._makeLine(originX, midY, childX, midY)
      this._makeLine(childX, midY, childX, childY)
    } else {
      // Branch — horizontal bar + drops
      const childXs = childRects.map(r => r.left + r.width / 2)
      const minX = Math.min(...childXs)
      const maxX = Math.max(...childXs)
      this._makeLine(minX, midY, maxX, midY)

      childRects.forEach(r => {
        const cx = r.left + r.width / 2
        this._makeLine(cx, midY, cx, r.top)
      })
    }
  },

  _makeLine(x1, y1, x2, y2, dashed) {
    const line = document.createElementNS(SVG_NS, "line")
    line.setAttribute("x1", x1)
    line.setAttribute("y1", y1)
    line.setAttribute("x2", x2)
    line.setAttribute("y2", y2)
    line.setAttribute("stroke", "rgba(128,128,128,0.4)")
    line.setAttribute("stroke-width", "1.5")
    if (dashed) line.setAttribute("stroke-dasharray", "4")
    this._svg.appendChild(line)
    return line
  },

  _toLocal(rect, containerRect) {
    return {
      left: rect.left - containerRect.left + this.el.scrollLeft,
      top: rect.top - containerRect.top + this.el.scrollTop,
      right: rect.right - containerRect.left + this.el.scrollLeft,
      bottom: rect.bottom - containerRect.top + this.el.scrollTop,
      width: rect.width,
      height: rect.height,
    }
  },

  _scrollToFocus() {
    setTimeout(() => {
      const focus = this._container?.querySelector("[data-focus='true']")
      if (focus) {
        focus.scrollIntoView({ behavior: "smooth", block: "center", inline: "center" })
      }
    }, 50)
  },
}
```

- [ ] **Step 2: Register hook in app.js**

In `assets/js/app.js`, add:
```javascript
import { GraphConnector } from "./graph_connector"
```

Update the hooks object — add `GraphConnector`, keep `TreeConnector` for now (removed in cleanup task):
```javascript
hooks: { ...colocatedHooks, FuzzyFilter, TreeConnector, GraphConnector, PhotoTagger, PersonHighlight, Swipe, TrixEditor, TextareaAutogrow },
```

- [ ] **Step 3: Commit**

```
git commit -m "Add GraphConnector JS hook for SVG connector drawing"
```

---

## Task 5: Create Graph Rendering Components

**Files:**
- Create: `lib/web/live/family_live/graph_component.ex`

- [ ] **Step 1: Create graph_component.ex**

This component renders the CSS Grid layout. It iterates over GraphNodes and places each in its grid cell. Person cards reuse the visual treatment from the old person_card_component but in a simpler structure.

```elixir
# lib/web/live/family_live/graph_component.ex
defmodule Web.FamilyLive.GraphComponent do
  use Web, :html

  alias Ancestry.People.GraphNode

  @doc "Renders the full DAG grid with person cards and separators."
  attr :graph, :map, required: true
  attr :family_id, :integer, required: true
  attr :organization, :map, required: true

  def graph_canvas(assigns) do
    ~H"""
    <div
      id="graph-canvas"
      phx-hook="GraphConnector"
      data-edges={Jason.encode!(@graph.edges)}
      class="relative overflow-auto hide-scrollbar p-6"
    >
      <div
        data-graph-grid
        style={"display:grid; grid-template-columns:repeat(#{@graph.grid_cols}, minmax(120px, auto)); grid-template-rows:repeat(#{@graph.grid_rows}, auto); gap:16px 12px;"}
      >
        <.graph_cell
          :for={node <- @graph.nodes}
          node={node}
          family_id={@family_id}
          organization={@organization}
        />
      </div>
    </div>
    """
  end

  attr :node, GraphNode, required: true
  attr :family_id, :integer, required: true
  attr :organization, :map, required: true

  defp graph_cell(%{node: %{type: :separator}} = assigns) do
    ~H"""
    <div
      style={"grid-column:#{@node.col + 1}; grid-row:#{@node.row + 1};"}
      class="border border-dashed border-base-content/5 rounded-ds-sharp min-h-[60px]"
    >
    </div>
    """
  end

  defp graph_cell(%{node: %{type: :person}} = assigns) do
    ~H"""
    <div
      id={@node.id}
      data-node-id={@node.id}
      data-focus={to_string(@node.focus)}
      style={"grid-column:#{@node.col + 1}; grid-row:#{@node.row + 1};"}
      class="min-h-[60px]"
    >
      <.person_card
        node={@node}
        family_id={@family_id}
        organization={@organization}
      />
    </div>
    """
  end

  attr :node, GraphNode, required: true
  attr :family_id, :integer, required: true
  attr :organization, :map, required: true

  defp person_card(assigns) do
    # Extract person from node for display
    assigns = assign(assigns, :person, assigns.node.person)

    ~H"""
    <button
      phx-click="focus_person"
      phx-value-person-id={@person.id}
      class={[
        "w-full rounded-ds-sharp border bg-base-200 p-2 text-left transition-all",
        "hover:ring-1 hover:ring-ds-primary/50",
        gender_border_class(@person),
        @node.focus && "ring-2 ring-ds-primary scale-105",
        @node.duplicated && "opacity-50 border-dashed"
      ]}
    >
      <%!-- Has more up indicator --%>
      <div :if={@node.has_more_up} class="flex justify-center -mt-1 mb-1">
        <.icon name="hero-chevron-up" class="w-3 h-3 text-base-content/40" />
      </div>

      <div class="flex items-center gap-2">
        <%!-- Photo or placeholder --%>
        <div class="w-8 h-8 rounded-full bg-base-300 flex items-center justify-center flex-shrink-0 overflow-hidden">
          <%= if @person.photo do %>
            <img src={@person.photo} class="w-full h-full object-cover" />
          <% else %>
            <.icon name={gender_icon(@person)} class={["w-4 h-4", gender_icon_class(@person)]} />
          <% end %>
        </div>

        <div class="min-w-0 flex-1">
          <p class="text-sm font-medium truncate">
            <%= @person.first_name %> <%= @person.last_name %>
          </p>
          <p :if={format_life_span(@person)} class="text-xs text-base-content/60">
            <%= format_life_span(@person) %>
          </p>
          <p :if={@node.duplicated} class="text-xs text-base-content/40 italic">
            (duplicated)
          </p>
        </div>

        <%!-- Navigate to person page --%>
        <.link
          navigate={~p"/org/#{@organization.id}/people/#{@person.id}"}
          class="flex-shrink-0 text-base-content/40 hover:text-ds-primary"
          phx-click={JS.stop_propagation()}
        >
          <.icon name="hero-arrow-top-right-on-square" class="w-4 h-4" />
        </.link>
      </div>

      <%!-- Has more down indicator --%>
      <div :if={@node.has_more_down} class="flex justify-center mt-1 -mb-1">
        <.icon name="hero-chevron-down" class="w-3 h-3 text-base-content/40" />
      </div>
    </button>
    """
  end

  defp gender_border_class(%{gender: "male"}), do: "border-t-2 border-t-blue-400"
  defp gender_border_class(%{gender: "female"}), do: "border-t-2 border-t-pink-400"
  defp gender_border_class(_), do: "border-t-2 border-t-base-content/20"

  defp gender_icon(%{gender: "male"}), do: "hero-user"
  defp gender_icon(%{gender: "female"}), do: "hero-user"
  defp gender_icon(_), do: "hero-user"

  defp gender_icon_class(%{gender: "male"}), do: "text-blue-400"
  defp gender_icon_class(%{gender: "female"}), do: "text-pink-400"
  defp gender_icon_class(_), do: "text-base-content/40"

  defp format_life_span(person) do
    birth = person.birth_year
    death = person.death_year

    case {birth, death} do
      {nil, nil} -> nil
      {b, nil} -> "#{b} —"
      {nil, d} -> "— #{d}"
      {b, d} -> "#{b} — #{d}"
    end
  end
end
```

- [ ] **Step 2: Commit**

```
git commit -m "Add GraphComponent for CSS Grid DAG rendering"
```

---

## Task 6: Update LiveView, Template, and Wire Up

**Files:**
- Modify: `lib/web/live/family_live/show.ex`
- Modify: `lib/web/live/family_live/show.html.heex`
- Modify: `test/web/live/family_live/show_test.exs`

- [ ] **Step 1: Update show.ex**

Replace `tree` assign with `graph`. Update `refresh_graph_and_tree/1` to build the new PersonGraph. Update event handlers that reference `@tree`.

Key changes:
- `assign(:tree, ...)` → `assign(:graph, ...)`
- `PersonGraph.build(focus, fg)` now returns the flat struct with nodes/edges
- Remove references to `@tree.ancestors`, `@tree.center`, `@tree.descendants`
- Remove `import Web.FamilyLive.PersonCardComponent` (line 16) and add `import Web.FamilyLive.GraphComponent`
- Rename `refresh_graph_and_tree/1` → `refresh_graph/1`

- [ ] **Step 2: Update show.html.heex**

Replace the tree canvas section (lines ~171-239) with the new graph component:

```heex
<%!-- Replace the old #tree-canvas section with: --%>
<.graph_canvas
  :if={@graph}
  graph={@graph}
  family_id={@family.id}
  organization={@current_scope.organization}
/>
```

Import the GraphComponent at the top of the LiveView or in web.ex.

- [ ] **Step 3: Update show_test.exs**

Replace assertions that reference `tree` with `graph`. Remove assertions on nested struct fields.

- [ ] **Step 4: Start dev server and test manually**

Run: `iex -S mix phx.server`
Navigate to a family show page. Verify:
- Grid renders with person cards
- Dotted separator borders visible for debugging
- SVG connectors drawn between parents and children
- Focus person highlighted
- Scroll to focus works
- Clicking a person re-centers the graph

- [ ] **Step 5: Commit**

```
git commit -m "Wire up DAG grid rendering in FamilyLive.Show"
```

---

## Task 7: Clean Up Old Code

**Files:**
- Delete: `lib/web/live/family_live/person_card_component.ex`
- Delete: `assets/js/tree_connector.js`
- Modify: `assets/js/app.js` — remove TreeConnector import and hook
- Modify: any files that import/alias PersonCardComponent

- [ ] **Step 1: Remove TreeConnector from app.js**

Remove the import line and the hook from the hooks object.

- [ ] **Step 2: Delete old files**

```bash
rm lib/web/live/family_live/person_card_component.ex
rm assets/js/tree_connector.js
```

- [ ] **Step 3: Fix any compilation errors**

Run: `mix compile --warnings-as-errors`
Fix any remaining references to deleted modules.

- [ ] **Step 4: Commit**

```
git commit -m "Remove old TreeView components and TreeConnector hook"
```

---

## Task 8: E2E Tests for Graph View

**Files:**
- Create or modify: `test/user_flows/family_graph_test.exs`

Per project convention (CLAUDE.md): "Every new or changed user flow must have E2E tests in `test/user_flows/`." See `test/user_flows/CLAUDE.md` for conventions and patterns.

- [ ] **Step 1: Write E2E tests for the graph view**

Cover these user flows:
- **View graph:** Navigate to family show page, verify graph canvas renders with person cards
- **Re-center:** Click a person card, verify URL updates and focus changes
- **Navigate to person:** Click the navigation icon on a card, verify navigation to person page
- **Depth controls:** Change ancestor/descendant depth, verify graph updates
- **Has more indicators:** With truncated depth, verify indicator icons appear

Use `test_id/1` for key elements. Add `test_id` attributes to the graph component if not already present:
- `test_id("graph-canvas")` on the grid container
- `test_id("person-card-#{person.id}")` on each person card

- [ ] **Step 2: Run E2E tests**

Run: `mix test test/user_flows/family_graph_test.exs --trace`

- [ ] **Step 3: Commit**

```
git commit -m "Add E2E tests for DAG graph view"
```

---

## Task 9: Run Full Test Suite and Precommit

**Files:**
- Potentially any files with compilation warnings

- [ ] **Step 1: Run precommit**

Run: `mix precommit`
This runs compile (warnings-as-errors), deps cleanup, format, and tests.

- [ ] **Step 2: Fix any issues**

Address compilation warnings, formatting issues, and test failures.

- [ ] **Step 3: Final commit**

```
git commit -m "Fix warnings and ensure all tests pass after DAG grid migration"
```

---

## Implementation Notes

### Key Learnings to Apply (from `docs/learnings.jsonl`)

- **`morphdom-stable-ids-for-loops`**: Every node wrapper div MUST have `id={node.id}`. For duplicated persons, node IDs must be unique (e.g., `"person-42"` vs `"person-42-dup"`).
- **`safe-dom-in-hooks`**: Use `document.createElementNS` for SVG elements. Never `innerHTML`.
- **`hook-destroyed-must-guard-state`**: Guard `destroyed()` with `if (!this._observer) return`.
- **`at-limit-simplified-path-data-loss`**: At depth boundaries, query ALL partner types.
- **`js-hook-native-types`**: Edges are JSON-encoded (all strings). No type coercion issues.

### Existing Conventions
- Tests use `family_fixture()`, `People.create_person()`, `Relationships.create_relationship()` — check existing test helpers in `test/support/`.
- Person struct has `gender`, `first_name`, `last_name`, `birth_year`, `death_year`, `photo` fields.
- Routes use `/org/:org_id/families/:family_id` pattern.
- Design system tokens: `rounded-ds-sharp`, `ring-ds-primary`, `bg-base-200`, etc.
