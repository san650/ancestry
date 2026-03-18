# Family Tree Canvas View — Design

## Overview

Add a visual family tree canvas to the FamilyLive.Show page. The canvas renders people and their relationships as a graph using HTML/CSS grid, with a side panel for galleries and people management.

Read-only canvas for this iteration. Interactive "Add Parent/Spouse" placeholders planned for a future iteration.

## Graph Data Model

### Module: `Ancestry.People.FamilyGraph`

Pure computation module — takes people and relationships, returns a grid struct. No database access.

**Vertex types:**

- **Person node** — each person appears exactly once. Rendered as a card with avatar, name, dates.
- **Union node** `{person_a_id, person_b_id, :partner | :ex_partner}` — invisible connector between two partners. Every partnership (current AND ex) creates one. Children descend from the union node.

**Edge types:**

- **Horizontal (partner link):** Person ↔ Union. Rendered as a horizontal line.
- **Vertical (child link):** Union → Child's person node. Rendered as a vertical line downward.
- **Solo child link:** Person → Child. For children with no known co-parent.

**Ex-partner chains:** A person with multiple partners/ex-partners forms a horizontal chain:

```
[A]---<union:A+B>---[B]---<union:B+C>---[C]---<union:B+D>---[D]
          |                    |                    |
      [child-AB]          [child-BC]           [child-BD]
```

Person B appears once, connected horizontally to all their unions.

**Unconnected people** (no relationships) are collected separately and rendered as a flat list below the tree.

### Build process

1. Load all people for the family + all relationships between them
2. Create a person node for each person
3. Create a union node for each partner/ex-partner relationship
4. For each child, find which union (pair of parents) they belong to. If only one parent known, add a solo child edge.
5. Use `:digraph_utils.components/1` to find disconnected subgraphs
6. Assign generations via BFS from root nodes (in-degree 0)

## Grid-Based Layout

Instead of absolute positioning, the algorithm maps every node to a cell in a 2D CSS grid.

**Grid dimensions:**

- **Rows** = number of generations
- **Columns** = widest horizontal span across all generations

**Cell contents:**

- Person card
- Union connector (styled element between partners)
- Horizontal connector (line segment)
- Vertical connector (line segment)
- Corner/T connector (for branching lines)
- Empty

**Algorithm:**

1. BFS assigns each person a generation (row)
2. For each generation, lay out partnership chains: `[person] [h-line] [union] [h-line] [person]` — each element is one column
3. Children of a union are centered below it, with horizontal connectors between siblings
4. Track max column count across all rows — that's the grid width
5. Narrower rows are centered within the grid

**Connector cell types:**

| Type | CSS |
|---|---|
| `horizontal` | `border-bottom` centered at 50% height |
| `vertical` | `border-right` centered at 50% width |
| `top_right` / `top_left` | Corner turns via two borders |
| `t_down` | Horizontal line with a vertical drop |
| `bottom_right` / `bottom_left` | Bottom corners |

Connectors use theme-aware colors (`border-zinc-300 dark:border-zinc-600`).

**Output struct:**

```elixir
%FamilyGraph{
  grid: %{
    rows: integer,
    cols: integer,
    cells: %{{row, col} => %Cell{type: atom, data: map}}
  },
  components: [[node_ids], ...],
  unconnected: [%Person{}, ...]
}
```

**CSS rendering:**

```css
.family-grid {
  display: grid;
  grid-template-columns: repeat(var(--cols), minmax(120px, 1fr));
  grid-template-rows: repeat(var(--rows), auto);
  overflow: auto;
}
```

## Page Layout

```
+-------------------------------------+------------------+
|                                      |  Right Panel     |
|         Canvas (scrollable)          |                  |
|                                      |  Galleries       |
|   [Connected component 1 grid]       |  + New Gallery   |
|   [Connected component 2 grid]       |                  |
|                                      |  People          |
|   -- Unconnected --                  |  [fuzzy search]  |
|   [p] [p] [p] [p]                   |  + New Member    |
|                                      |  + Link Existing |
+-------------------------------------+------------------+
```

Mobile: side panel stacks below canvas. Unconnected list switches to vertical.

## LiveComponents

All presentation-only. Receive data as assigns, no business logic.

| Component | Responsibility |
|---|---|
| `CanvasComponent` | Scrollable container, renders TreeComponents + unconnected list |
| `TreeComponent` | One connected component as a CSS grid |
| `PersonCardComponent` | Person card: avatar, name, dates. Links to PersonLive.Show |
| `UnionConnectorComponent` | Visual connector between partners |
| `ConnectorCellComponent` | Line segments via CSS borders |
| `SidePanelComponent` | Right panel container |
| `GalleryListComponent` | Gallery list + "New Gallery" button |
| `PeopleListComponent` | Sorted people list, fuzzy search, "New Member" / "Link Existing" |

## Data Loading

**New context functions:**

`People.build_family_graph/1` — public API, orchestrates:

```elixir
def build_family_graph(family_id) do
  people = list_people_for_family(family_id)
  relationships = Relationships.list_relationships_for_family(family_id)
  FamilyGraph.build(people, relationships)
end
```

`Relationships.list_relationships_for_family/1` — single query joining through `family_members`:

```elixir
def list_relationships_for_family(family_id) do
  from(r in Relationship,
    join: fm_a in FamilyMember, on: fm_a.person_id == r.person_a_id and fm_a.family_id == ^family_id,
    join: fm_b in FamilyMember, on: fm_b.person_id == r.person_b_id and fm_b.family_id == ^family_id,
    preload: [:person_a, :person_b]
  )
  |> Repo.all()
end
```

**No new dependencies. No migrations. No schema changes.**

## Files

**New:**

- `lib/ancestry/people/family_graph.ex` — graph building + grid layout algorithm
- `lib/web/live/family_live/canvas_component.ex`
- `lib/web/live/family_live/tree_component.ex`
- `lib/web/live/family_live/person_card_component.ex`
- `lib/web/live/family_live/union_connector_component.ex`
- `lib/web/live/family_live/connector_cell_component.ex`
- `lib/web/live/family_live/side_panel_component.ex`
- `lib/web/live/family_live/gallery_list_component.ex`
- `lib/web/live/family_live/people_list_component.ex`

**Modified:**

- `lib/ancestry/people.ex` — add `build_family_graph/1`
- `lib/ancestry/relationships.ex` — add `list_relationships_for_family/1`
- `lib/web/live/family_live/show.ex` — new layout with canvas + side panel
