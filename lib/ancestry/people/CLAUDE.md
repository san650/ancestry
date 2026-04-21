# TreeView: Family Graph Visualization

This document is the authoritative reference for implementing the TreeView — the visual family tree displayed on the Family Show page. It describes the problem domain, the data model, the graph-to-tree conversion algorithm, rendering approaches, and the many nuances that make genealogy trees different from generic tree visualizations.

---

## Table of Contents

1. [Problem Domain](#problem-domain)
2. [What the TreeView Must Display](#what-the-treeview-must-display)
3. [The Underlying Data: A Graph with Cycles](#the-underlying-data-a-graph-with-cycles)
4. [Graph-to-Tree Conversion Algorithm](#graph-to-tree-conversion-algorithm)
5. [ASCII Art Examples](#ascii-art-examples)
6. [Rendering Approaches (5 Proposals)](#rendering-approaches)
7. [Current Implementation and Its Problems](#current-implementation-and-its-problems)
8. [Nuances and Edge Cases](#nuances-and-edge-cases)
9. [Glossary](#glossary)

---

## Problem Domain

A family tree visualization for a genealogy application must solve a fundamentally different problem than a generic tree widget. The data is a **directed graph** (not a tree) because:

- A person has **two biological parents** (not one parent like a file in a directory).
- A person can appear in **multiple roles** (e.g., as someone's uncle AND as someone else's grandfather).
- **Pedigree collapse** means the same ancestor can be reached through multiple lineage paths (e.g., when cousins marry).
- **Partner relationships** are horizontal connections that create non-hierarchical edges.
- **Blended families** (ex-partners, previous partners, solo children) create asymmetric branching.

The TreeView is NOT a tree in the computer science sense. It is a **person-centered, role-based flattening of a directed graph** where cycles are removed by cloning nodes into every position (role) they occupy.

---

## What the TreeView Must Display

### Core Requirements

1. **Person-centered**: A focus person is selected. The tree expands outward from them.
2. **Ancestors expand upward**: Parents above, grandparents above them, etc. Each generation at a distinct vertical level.
3. **Descendants expand downward**: Children below, grandchildren below them, etc.
4. **Couples are paired horizontally**: Partners (married, in a relationship) sit side-by-side with a visual connection.
5. **Lateral relatives appear alongside the direct line**: Siblings, uncles/aunts, cousins when the `other` depth setting allows it.
6. **Connector lines** link parents to children and connect ancestor trees to the couple below.
7. **Depth controls**: Users can adjust how many generations of ancestors, descendants, and lateral relatives to show.

### Visual Constraints

- **Generational alignment**: ALL people of the same generation MUST be at the same vertical Y coordinate. This is the single most important visual rule. A grandparent must never appear at the same visual level as a parent or great-grandparent.
- **Horizontal centering**: Children should be roughly centered under their parents.
- **Responsive**: Works on both mobile (compact cards, single column scroll) and desktop (full tree with side panel).
- **Scrollable**: Large trees overflow the viewport. The canvas must be scrollable in both directions with the focus person scrolled into view.
- **Interactive**: Clicking a person card re-centers the tree on that person (push_patch navigation).

### What It Looks Like

The canonical layout for a 3-generation ancestor tree with the focus person at the bottom:

```
Generation 3:    [PGP-A ═ PGP-B]            [MGP-A ═ MGP-B]
                       |                           |
Generation 2:     [Dad]    [Uncle]         [Mom]    [Aunt]
                    |                        |
                    └────── [Dad ═ Mom] ─────┘
                                |
Generation 1:        [Me]   [Sibling]
                      |
Generation 0:    [My Child]
```

Key observations:
- Generation 3 has two separate couples (paternal and maternal grandparents).
- Generation 2 shows each couple's children. Dad and Mom are "pass-throughs" — they appear both as children of their parents AND as the coupled pair below.
- The focus person's couple (Dad ═ Mom) sits between the two ancestor branches.
- Children of the focus person appear below.

---

## The Underlying Data: A Graph with Cycles

### Relationship Types

From `Ancestry.Relationships`:

| Type | Direction | Semantics |
|------|-----------|-----------|
| `"parent"` | Directed: person_a → person_b | person_a is parent of person_b |
| `"married"` | Symmetric | Active partner |
| `"relationship"` | Symmetric | Active partner (non-married) |
| `"divorced"` | Symmetric | Former partner |
| `"separated"` | Symmetric | Former partner |

### In-Memory Graph (`FamilyGraph`)

`Ancestry.People.FamilyGraph` loads all people and relationships for a family into indexed maps with exactly 2 SQL queries:

```
people_by_id:      %{person_id => %Person{}}
parents_by_child:  %{child_id  => [{%Person{}, %Relationship{}}]}
children_by_parent:%{parent_id => [%Person{}]}
partners_by_person:%{person_id => [{%Person{}, %Relationship{}}]}
```

The graph is **bidirectional for partners** (if A partners B, both A and B have the entry) but **directed for parent-child** (parent_id → child_id, and child_id → parent_ids).

### Where Cycles Appear

#### Pedigree Collapse

When two people who share a common ancestor have children together. Example: first cousins who marry.

```
         [A ═ B]
         /     \
       [C]     [D]
         \     /
         [E ═ F]     ← E and F are first cousins
            |
           [G]       ← G has A and B as BOTH paternal and maternal grandparents
```

Person G's ancestor tree: walking up from G through E reaches A and B. Walking up through F also reaches A and B. In a naive tree rendering, A and B would appear twice (once on each side). This is **correct behavior** — the tree shows roles, not unique people.

#### In-Law Loops

Partner relationships create horizontal connections that can form cycles:

```
[A] ─parent→ [B] ─married→ [C] ─parent← [D]
```

If D is also related to A by blood, there's a cycle. The tree breaks these by only following parent edges upward and child edges downward from the focus person.

#### Half-Sibling Networks

```
     [Dad]     [Mom]     [StepDad]
       \       / \         /
        [Me]     [Half-Sibling]
```

Me and Half-Sibling share Mom but have different fathers. When expanding laterals, Half-Sibling appears as a child of Mom+StepDad.

---

## Graph-to-Tree Conversion Algorithm

### Overview

The algorithm has three phases:

1. **Build** (`PersonTree.build/3`): Recursive walk from the focus person outward, respecting depth limits. Produces a recursive data structure.
2. **Transform** (`PersonTree.to_family_groups/1`): Restructures the build output into a render-friendly format with ancestor trees above and children groups below.
3. **Render**: LiveView templates + JS connector hooks turn the data into visual HTML + SVG.

### Phase 1: Build

Starting from the focus person:

**Downward (descendants):**
```
build_family_unit_full(person, depth, max_depth, graph):
  1. Find active partners → sort by marriage year (latest first)
  2. Latest partner = main partner; rest = previous_partners
  3. Find former partners (divorced/separated) = ex_partners
  4. For each partner group: get children_of_pair → recurse
  5. Get solo_children (no co-parent) → recurse
  6. At max_depth: just check has_more?, don't recurse
```

**Upward (ancestors):**
```
build_ancestor_tree(person_id, depth, max_depth, other_depth, children_depth, graph):
  1. Find parents of person_id → (person_a, person_b)
  2. If no parents → nil (leaf)
  3. For each parent with further ancestors: recurse upward
  4. If depth ≤ other_depth: find other_children (siblings of the direct-line child)
  5. Return {couple, parent_trees, other_children}
```

**Key invariant**: The build phase never follows partner edges to discover new people. Partners are found by looking up the person's partner relationships. Ancestors are found by looking up parent relationships. This prevents infinite loops.

### Phase 2: Transform (to_family_groups)

The build output is ancestor-centric (nested downward from the oldest ancestors). The transform restructures it for rendering:

```
build_group(ancestor_node, center_unit):
  1. Collect lateral entries (other_children as non-pass-through)
  2. Add center_unit as the direct-line child (non-pass-through)
  3. For each parent_tree entry:
     a. Determine side (left for person_a, right for person_b)
     b. Recursively build ancestor_tree_entry with laterals + pass-through
     c. Order: person_a's laterals left + pass-through right,
               person_b's pass-through left + laterals right
  4. Return {couple, ancestor_trees, children_groups}
```

**Pass-through nodes**: An empty placeholder in the children_groups of an ancestor couple. It marks where the direct-line child "passes through" — connecting the ancestor tree's branch connector to the person card in the couple below. This is how the JS knows to draw a line from the grandparent level down to the parent card.

### Phase 3: Render

The `family_group_tree` component renders recursively:

```
<family_group_tree group={group}>
  IF group has ancestor_trees:
    <flex row items-end>
      <ancestor-tree-1>  (recursive family_group_tree)
      <couple-card>       (the couple at this level)
      <ancestor-tree-2>  (recursive family_group_tree)
    </flex>
  ELSE:
    <couple-card>
  END
  
  IF group has children_groups:
    <children-row>
      FOR each child_group:
        IF pass_through:  <empty placeholder column>
        ELSE:             <family_subtree unit={child_group.unit}>
      END
    </children-row>
  END
</family_group_tree>
```

---

## ASCII Art Examples

### Example 1: Simple Nuclear Family (no ancestors beyond parents)

Focus: Me. Parents: Dad, Mom. Siblings: Sister.

```
Settings: ancestors=1, children=0, other=1

              ┌──────────────────┐
              │   Dad  ═  Mom    │  ← couple card
              └────────┬─────────┘
                 ┌─────┴─────┐
                 │           │
              ┌──┴──┐    ┌──┴───┐
              │ Me  │    │Sister│  ← children row
              │(foc)│    │      │
              └─────┘    └──────┘
```

Data flow:
- `ancestor_tree` = `{couple: {Dad, Mom}, parent_trees: [], other_children: [Sister]}`
- `children_groups` = `[{unit: Sister, pass_through: false}, {unit: Me-center, pass_through: false}]`
- No `ancestor_trees` because parents have no known parents.

### Example 2: Two Generations of Ancestors (symmetric)

Focus: Me. Dad's parents: GP-A, GP-B. Mom's parents: MGP-A, MGP-B.

```
Settings: ancestors=2, children=0, other=0

   ┌────────────────┐                ┌────────────────┐
   │ GP-A  ═  GP-B  │                │MGP-A  ═  MGP-B │
   └───────┬────────┘                └───────┬────────┘
           │                                 │
        [Dad]*                            [Mom]*        ← pass-throughs
           │                                 │
           └──────────┐  ┌───────────────────┘
                      │  │
                 ┌────┴──┴────┐
                 │  Dad ═ Mom │  ← couple card (parents)
                 └─────┬──────┘
                       │
                    ┌──┴──┐
                    │ Me  │
                    │(foc)│
                    └─────┘
```

Notes:
- `[Dad]*` and `[Mom]*` are pass-through placeholders — they occupy space in the grandparent's children row and serve as endpoints for connector lines.
- The actual Dad and Mom person cards are rendered in the couple card between the two ancestor trees.
- The JS draws a line from each pass-through down to the corresponding person in the couple card.

### Example 3: Ancestors with Lateral Relatives (uncle, aunt)

Focus: Me. Uncle is Dad's sibling. Aunt is Mom's sibling.

```
Settings: ancestors=2, children=1, other=2

   ┌────────────────┐                       ┌────────────────┐
   │ GP-A  ═  GP-B  │                       │MGP-A  ═  MGP-B │
   └───────┬────────┘                       └───────┬────────┘
     ┌─────┴─────┐                            ┌─────┴─────┐
     │           │                            │           │
  ┌──┴───┐   [Dad]*                        [Mom]*     ┌──┴──┐
  │Uncle │                                            │Aunt │
  │      │                                            │     │
  └──┬───┘                                            └──┬──┘
     │                                                   │
  ┌──┴───┐                                            ┌──┴──┐
  │Cousin│                                            │Cous.│
  └──────┘                                            └─────┘

                    ┌──────────────┐
                    │  Dad  ═  Mom │
                    └──────┬───────┘
                     ┌─────┴─────┐
                     │           │
                  ┌──┴──┐    ┌──┴───┐
                  │ Me  │    │Sister│
                  │(foc)│    │      │
                  └─────┘    └──────┘
```

Notes:
- **Left branch**: GP's children row has `[Uncle, Dad*]`. Uncle is a lateral, Dad* is a pass-through. Uncle's family unit expands to show Cousin below.
- **Right branch**: MGP's children row has `[Mom*, Aunt]`. Mom* is a pass-through (placed LEFT because she's person_b's side, toward center). Aunt is a lateral.
- **Ordering rule for laterals**: On person_a's side (left tree), laterals go LEFT of pass-through. On person_b's side (right tree), laterals go RIGHT of pass-through. This keeps pass-throughs toward the center where the parents couple card sits.

### Example 4: Asymmetric Ancestors (only one parent has known parents)

Focus: Me. Dad has parents, Mom does not.

```
Settings: ancestors=2, children=0, other=0

         ┌────────────────┐
         │ GP-A  ═  GP-B  │
         └───────┬────────┘
                 │
              [Dad]*

         ┌──────────────┐
         │  Dad  ═  Mom │
         └──────┬───────┘
                │
             ┌──┴──┐
             │ Me  │
             └─────┘
```

Notes:
- Only one `ancestor_tree` exists (for Dad's side).
- The couple card sits below with only one tree above it.
- This is a common real-world scenario — one lineage is well-documented, the other is not.

### Example 5: Three Generations of Ancestors (deep tree)

Focus: Me. Three levels of paternal ancestors, two levels of maternal.

```
Settings: ancestors=3, children=0, other=0

┌──────────────────┐  ┌──────────────────┐
│GGP-A1 ═ GGP-B1  │  │GGP-A2 ═ GGP-B2  │
└────────┬─────────┘  └────────┬─────────┘
         │                     │
      [GP-A]*               [GP-B]*

      ┌────────────────┐                       ┌────────────────┐
      │ GP-A  ═  GP-B  │                       │MGP-A  ═  MGP-B │
      └───────┬────────┘                       └───────┬────────┘
              │                                        │
           [Dad]*                                   [Mom]*

                       ┌──────────────┐
                       │  Dad  ═  Mom │
                       └──────┬───────┘
                              │
                           ┌──┴──┐
                           │ Me  │
                           └─────┘
```

Notes:
- **Three visual layers of ancestor trees**:
  - Top: Great-grandparents (GGP couples)
  - Middle: Grandparents (GP couples, with ancestor trees above them)
  - Bottom: Parents couple
- Each ancestor tree recurses: GP-A's tree contains GGP couples above it, which in turn could have their own ancestor trees.
- The tree width doubles with each ancestor generation: 1 couple → 2 couples → 4 couples → 8 couples.

### Example 6: Pedigree Collapse (same ancestor through both parents)

Focus: G. Parents E and F are first cousins (they share grandparents A and B).

```
The actual graph (with cycle):

         [A ═ B]
         /     \
       [C]     [D]
       |         |
       [E]     [F]
         \     /
          [G]

The rendered tree (cycle broken by cloning):

   ┌──────────┐     ┌──────────┐
   │  A  ═  B │     │  A' ═ B' │    ← A,B appear TWICE (cloned)
   └────┬─────┘     └────┬─────┘
        │                 │
     [C]*              [D]*

   ┌──────────────┐
   │   C   ═   D  │
   └──────┬───────┘
          │
   ┌──────┴──────┐
   │  E   ═   F  │
   └──────┬──────┘
          │
       ┌──┴──┐
       │  G  │
       │(foc)│
       └─────┘
```

Notes:
- A and B appear twice — once as C's parents (left tree) and once as D's parents (right tree).
- This is correct and expected. The tree shows **roles**: "E's grandparents" and "F's grandparents" happen to be the same people, but they occupy two distinct positions in the visual tree.
- The person cards for A and A' would have the same person_id and clicking either would navigate to the same person.

### Example 7: Blended Family (ex-partner with children)

Focus: Me. Dad was previously married to ExWife and has a half-sibling.

```
Settings: ancestors=1, children=0, other=0

              ┌───────────────────────────────────────┐
              │ ExWife ╌╌╌ Dad  ═  Mom                │  ← couple card
              └──┬─────╌╌──┬───────┬──────────────────┘
                 │          │      │
              ┌──┴──┐   ┌──┴──┐ ┌─┴────┐
              │Half │   │ Me  │ │Sister│
              │Sibl.│   │(foc)│ │      │
              └─────┘   └─────┘ └──────┘

Legend:  ═ active partner   ╌╌╌ ex-partner (dashed line)
```

Notes:
- ExWife appears in the couple card to the left of Dad, connected by a dashed line.
- Half-sibling's connector line originates from the ExWife-Dad midpoint.
- Partner children's connector originates from the Dad-Mom midpoint.
- `data-line-origin` attributes differentiate the line groups: `"partner"`, `"ex-42"`, `"solo"`.

### Example 8: Wide Tree with Cousins at Multiple Levels

Focus: Me. Showing uncle's family and great-uncle's family.

```
Settings: ancestors=3, children=2, other=3

┌──────────────┐
│GGP-A ═ GGP-B │
└──────┬───────┘
 ┌─────┴──────────────┐
 │                     │
┌┴────────┐        [GP-A]*
│Gt-Uncle │
│  ═ Wife │
└──┬──────┘
   │
┌──┴─────┐
│2ndCous.│
└────────┘

        ┌────────────────┐
        │ GP-A  ═  GP-B  │
        └───────┬────────┘
          ┌─────┴─────┐
          │           │
       ┌──┴───┐   [Dad]*
       │Uncle │
       │═Wife │
       └──┬───┘
          │
       ┌──┴───┐
       │Cousin│
       └──────┘

                    ┌──────────────┐
                    │  Dad  ═  Mom │
                    └──────┬───────┘
                     ┌─────┴─────┐
                     │           │
                  ┌──┴──┐    ┌──┴───┐
                  │ Me  │    │Sister│
                  └──┬──┘    └──────┘
                     │
                  ┌──┴──────┐
                  │My Child │
                  └─────────┘
```

Notes:
- **Three levels of lateral expansion**: Great-uncle at the great-grandparent level, Uncle at the grandparent level, Sister at the parent level.
- Each lateral can have their own descendants, creating nested `family_subtree` components.
- The tree width grows rapidly. At `other=3` with 3 ancestor generations, the top level could show great-grandparents' OTHER children, which means great-aunts/uncles with their own family units.

---

## Rendering Approaches

### The Core Challenge

The fundamental rendering challenge is **generational alignment**: ensuring all people of the same generation appear at the same Y coordinate, while handling:
- Variable-width subtrees (one branch might be much wider than the other)
- Couple pairing (horizontal connections within a generation)
- Connector lines between generations
- Responsive design (mobile vs desktop)
- LiveView compatibility (server-rendered templates, efficient DOM patching)

Below are five approaches ordered from least to most JavaScript dependency.

---

### Approach 1: Pure CSS Grid with Generational Rows

**Concept**: Use a CSS Grid where each row is a generation. Compute which generation each person belongs to server-side in Elixir. Render all cards into their grid row, then draw connectors with a JS overlay (SVG).

```
display: grid;
grid-template-rows: repeat(N, auto);  /* one row per generation */
grid-template-columns: repeat(M, auto);  /* one column per card slot */
```

Each person card gets `grid-row: generation_number` and `grid-column: computed_slot`.

**Implementation**:
- Elixir computes a flat list of `{person, generation, column, role}` tuples.
- HEEX renders each card with inline `style="grid-row: N; grid-column: M"`.
- JS hook draws SVG connectors by reading card positions from the DOM.

**Pros**:
- Generational alignment is guaranteed by CSS Grid rows.
- Server-rendered — no layout flash, LiveView DOM patching works perfectly.
- Cards are real DOM elements — accessible, interactive, styled with Tailwind.
- Connectors can use the existing TreeConnector hook pattern.

**Cons**:
- Column computation is the hard part. Couples must occupy adjacent columns; children must be centered under parents. This is essentially implementing a Sugiyama layout algorithm in Elixir.
- Grid cells don't naturally support "couple grouping" — need wrapper elements or `grid-column: span 2`.
- Very wide trees create many empty cells (sparse grid).

**Complexity**: High (algorithm), Low (front-end).

---

### Approach 2: position:absolute with Elixir-Computed Coordinates

**Concept**: Compute absolute pixel positions for every card server-side in Elixir. Render cards with `position: absolute; left: Xpx; top: Ypx`. Draw connectors as SVG paths using the same coordinates.

**Implementation**:
- Elixir layout algorithm assigns `{x, y, width, height}` to each node.
- HEEX renders a container with `position: relative` and cards with absolute positioning.
- Connector SVG paths are computed server-side (Elixir knows all coordinates).
- JS hook only handles scroll-to-focus and ResizeObserver for container sizing.

**Layout algorithm** (simplified Sugiyama):
```elixir
1. Assign generations (BFS from focus, parents = gen+1, children = gen-1)
2. Order nodes within each generation (minimize edge crossings)
3. Assign X coordinates (center children under parents, space couples)
4. Assign Y coordinates (fixed row height per generation)
5. Compute connector paths (vertical + horizontal SVG segments)
```

**Pros**:
- Zero JS for layout — instant render with no flash.
- Full server control — every pixel position is deterministic.
- SVG connectors computed server-side — no DOM measurement needed.
- LiveView patches only change the cards that moved.
- Works identically on mobile and desktop (just different card widths).

**Cons**:
- Must implement the layout algorithm from scratch in Elixir.
- Fixed pixel positions mean no CSS-responsive behavior — must recompute on resize.
- Card dimensions must be known at layout time (or use fixed dimensions).
- Complex to handle variable card heights (long names, photos vs placeholders).

**Complexity**: Very High (algorithm), Low (front-end).

---

### Approach 3: Flexbox Tree with JS Generational Alignment (Hybrid)

**Concept**: Keep the current HEEX flexbox rendering approach but add a JS hook that post-processes the DOM to enforce generational alignment. After LiveView renders, JS reads all cards, groups them by generation, and adjusts their `margin-top` or `transform: translateY()` to align rows.

**Implementation**:
- Server renders the tree with flexbox layout (current approach).
- Each card gets a `data-generation="N"` attribute.
- JS hook runs after mount/update:
  1. Query all cards, group by generation.
  2. Find the maximum Y among all cards in each generation.
  3. Apply `transform: translateY(offset)` to push shallower trees down.
- Connector lines are drawn after alignment (current TreeConnector approach).

```javascript
_alignGenerations() {
  const cards = this.el.querySelectorAll('[data-generation]')
  const genRows = {}
  for (const card of cards) {
    const gen = parseInt(card.dataset.generation)
    if (!genRows[gen]) genRows[gen] = []
    genRows[gen].push(card)
  }
  // For each generation, find max Y and align all cards to it
  for (const [gen, cards] of Object.entries(genRows)) {
    const maxY = Math.max(...cards.map(c => c.getBoundingClientRect().top))
    for (const card of cards) {
      const offset = maxY - card.getBoundingClientRect().top
      if (offset > 0) card.style.transform = `translateY(${offset}px)`
    }
  }
}
```

**Pros**:
- Minimal change from current implementation.
- Flexbox handles horizontal spacing naturally.
- JS only adjusts Y positions — doesn't replace the layout.
- HEEX templates stay mostly the same.
- Couples remain naturally grouped by the flexbox structure.

**Cons**:
- **Layout flash**: Cards render at wrong positions first, then jump. Can mitigate with `opacity: 0` until aligned, but adds complexity.
- Two layout passes (flexbox → JS correction) is fragile — edge cases with nested flex containers.
- Connector lines must be drawn after alignment, creating a dependency chain.
- Doesn't solve the fundamental issue of wide asymmetric trees causing horizontal misalignment.

**Complexity**: Medium (algorithm), Medium (front-end).

---

### Approach 4: JS Layout Library (relatives-tree) + HEEX Cards

**Concept**: Use `relatives-tree` (3.2 kB, MIT, zero deps) to compute layout coordinates in a JS hook. Server renders HEEX cards into a hidden container, then JS reads the data, computes layout, and positions cards using CSS transforms.

**Implementation**:
- Server passes the family data as a JSON blob via `data-tree-data` attribute.
- HEEX pre-renders all person cards into an invisible container.
- JS hook:
  1. Parse the JSON data into relatives-tree's input format.
  2. Call `calcTree(nodes, options)` to get positioned nodes + connectors.
  3. Move pre-rendered HEEX cards to computed positions via `transform: translate(x, y)`.
  4. Draw connector lines from the computed connector coordinates.

```javascript
import { calcTree } from 'relatives-tree'

mounted() {
  const data = JSON.parse(this.el.dataset.treeData)
  const tree = calcTree(data.nodes, { rootId: data.focusId })
  this._positionCards(tree.nodes)
  this._drawConnectors(tree.connectors)
}
```

**Pros**:
- Purpose-built for genealogy trees — understands spouses, siblings, parents, children.
- Tiny bundle size (3.2 kB) — negligible performance impact.
- Generational alignment is handled by the library.
- Keeps HEEX templates for card rendering — LiveView-friendly.
- Zero external dependencies.

**Cons**:
- Two rendering passes (HEEX render → JS reposition) — potential layout flash.
- Must serialize tree data to JSON — adds a data bridge between Elixir and JS.
- The library's layout algorithm may not match our exact visual preferences.
- Less control over fine-grained positioning (couple spacing, lateral placement).
- Library has ~55 GitHub stars — smaller community, potential maintenance risk.

**Complexity**: Low (algorithm — delegated), Medium (front-end integration).

---

### Approach 5: DAG Layout Library (d3-dag or dagre) + HEEX Cards

**Concept**: Model the family tree as a DAG (directed acyclic graph) with virtual "union" nodes for couples. Use d3-dag or dagre to compute optimal Sugiyama layered layout. Position HEEX cards using computed coordinates.

**Implementation**:
- In Elixir or JS, transform the family graph into a DAG:
  - Each person is a node.
  - Each couple creates a virtual "union" node.
  - Edges: parent → union, union → child.
- Feed the DAG to d3-dag's `sugiyama()` or dagre's `layout()`.
- Position HEEX cards at computed coordinates.
- Draw edges as computed by the library.

```
Person Graph:        DAG with Union Nodes:

  GP-A  ═  GP-B         GP-A   GP-B
                          \     /
                          [U-1]        ← virtual union node
                          /   \
                        Dad   Uncle
```

**Pros**:
- Mathematically optimal layout (minimizes edge crossings).
- Handles pedigree collapse natively — same node, multiple parents in DAG.
- Battle-tested libraries (dagre: 5.6K stars, d3-dag: 1.5K stars).
- Generational alignment is the core purpose of Sugiyama layout.

**Cons**:
- Couple rendering requires virtual "union" nodes — adds complexity and may not produce visually appealing couple spacing.
- Heavier than relatives-tree (dagre ~30 kB, d3-dag ~30-50 kB).
- These are general-purpose DAG layout libraries — not genealogy-specific. Need significant customization for partner pairing, lateral ordering, etc.
- The union-node pattern means couples aren't visually adjacent in the raw output — need post-processing.

**Complexity**: Medium (algorithm — custom DAG construction), High (front-end — visual customization).

---

### Approach Comparison Matrix

| Criteria | 1. CSS Grid | 2. Absolute | 3. Flex+JS | 4. relatives-tree | 5. d3-dag/dagre |
|----------|-------------|-------------|------------|-------------------|-----------------|
| Gen. alignment | CSS guarantee | Elixir guarantee | JS post-fix | Library handles | Library handles |
| Layout flash | None | None | Yes | Yes | Yes |
| JS dependency | SVG only | Scroll only | Alignment+SVG | Layout+SVG | Layout+SVG |
| Bundle size | 0 kB | 0 kB | 0 kB | 3.2 kB | 30-50 kB |
| Couple pairing | Manual | Manual | Current works | Library handles | Union nodes |
| Pedigree collapse | Clone nodes | Clone nodes | Clone nodes | Unknown | Native DAG |
| LiveView compat | Excellent | Excellent | Good | Good | Good |
| Algorithm effort | High | Very High | Medium | Low | Medium |
| Visual control | Full | Full | Full | Limited | Limited |
| Mobile support | CSS responsive | Recompute | CSS responsive | Recompute | Recompute |

### Chosen Approach: #2 — position:absolute with Elixir-Computed Coordinates

After evaluation, **Approach 2** was selected. The implementation plan is in `docs/plans/2026-04-20-treeview-absolute-layout-design.md`.

**Rationale:**
- Zero layout flash (positions computed server-side, rendered on first frame)
- Full visual control over every pixel position
- Eliminates 280+ lines of JS connector-drawing code (server-rendered SVG instead)
- Generational alignment is guaranteed by the math, not by CSS behavior
- Same algorithm works for desktop and mobile (different card-size constants)
- Handles all corner cases (pedigree collapse, asymmetric depth, ex-partners, laterals) with one algorithm

**Key architectural decision:** Couples stay compact (8px gap between partners). When ancestor trees above would pull partners apart, the couple centers at the midpoint and **bent connectors** bridge the gap. This produces the natural "hourglass" shape seen in professional genealogy applications.

---

## Current Implementation and Its Problems

### Architecture (as of 2026-04-20)

1. **PersonTree.build/3** → recursive data structure with ancestors upward, descendants downward.
2. **PersonTree.to_family_groups/1** → transforms into `{couple, ancestor_trees, children_groups}` for rendering.
3. **family_group_tree** component → recursive HEEX with `flex items-end` layout.
4. **TreeConnector** JS hook → SVG overlay drawing branch, pass-through, and couple connectors.

### Current Problems

1. **All ancestors appear at the same visual level**: The `flex items-end` alignment causes all ancestor trees to bottom-align regardless of their depth. A great-grandparent (generation 3) appears at the same Y as a grandparent (generation 2) because the shorter tree gets pushed down to align with the taller tree's bottom.

2. **No generational alignment**: People of the same generation are NOT at the same Y coordinate. This is the most critical visual failure. In the screenshot, 1870s great-grandparents are at the same level as 1950s parents.

3. **Flat appearance**: The tree looks like a single row of cards at the top with children below, rather than a proper multi-level hierarchy.

4. **Connector lines are ambiguous**: Without proper vertical separation between generations, the connector lines between parent and child cards are unclear.

5. **Width explosion**: With `other > 0`, the tree gets extremely wide because all lateral relatives at every ancestor level are rendered at the same visual row, rather than being properly tiered.

### Root Cause

The fundamental issue is that **flexbox cannot enforce generational alignment across independent subtrees**. When the left ancestor tree has 3 levels and the right has 2 levels, `flex items-end` aligns them at the bottom — but this means the 2-level tree's grandparents are at the same Y as the 3-level tree's parents.

The solution requires either:
- A layout system that knows about generations (CSS Grid rows, absolute positioning, or a layout library).
- A JS post-processing step that adjusts Y positions to enforce alignment.

---

## Nuances and Edge Cases

### 1. Pedigree Collapse (Duplicate Ancestors)

When the same person appears multiple times in the tree, each instance is an independent card. They share the same `person_id` and clicking either navigates to the same person. The current implementation handles this by cloning — each walk upward through a parent creates a fresh subtree, even if the ancestor was already visited.

**Trade-off**: Cloning is correct for display but means the visual tree grows wider than necessary. Some applications "merge" duplicate ancestors with a visual indicator, but this creates complex connector routing.

### 2. Asymmetric Depth

One parent's lineage may go back 5 generations while the other has only 1. The rendering must handle this gracefully:
- The deeper side's tree is taller.
- The shallower side should NOT be stretched to match.
- Generational alignment still applies — generation 2 on the left must be at the same Y as generation 2 on the right.

### 3. Single-Parent Ancestors

A person may have only one known parent. The couple card shows just one person card. The ancestor tree above has only one branch. The pass-through connects to the single parent.

### 4. Multiple Partner Groups

A person can have:
- One active partner (current married/relationship)
- Multiple previous partners (non-ex, sorted by marriage year)
- Multiple ex-partners (divorced/separated)

Each partner group's children are tracked separately. The couple card shows all partners in a horizontal row. Connector lines use different origins (`partner`, `prev-{id}`, `ex-{id}`, `solo`).

### 5. Width Management

At 3 ancestor generations with `other=2`, the top generation can have up to 8 couples (2^3), each with multiple lateral children. The tree can easily exceed 3000px wide. Current approach: horizontal scroll with `overflow-x: auto`.

Potential improvements:
- Collapse distant branches into summary nodes ("3 more...")
- On mobile, show only the direct line and expand on tap.
- Use a minimap for navigation.

### 6. Card Dimensions

Card dimensions differ between mobile (72px wide) and desktop (112px / 7rem). The layout algorithm must account for this. If using server-computed positions, the card width must be a known constant or the algorithm must accept it as a parameter.

### 7. Pass-Through vs. Duplicate Rendering

A parent who appears in an ancestor tree's children row (as a pass-through) AND in the couple card below is NOT rendered twice as a card. The pass-through is an empty placeholder (`min-w-28`) that occupies space for connector routing. The actual person card is only in the couple card.

### 8. Connector Line Types

| Connector | Source | Target | Style |
|-----------|--------|--------|-------|
| Branch | Couple card bottom | Children row top | Solid, vertical → horizontal → vertical |
| Pass-through | Pass-through column bottom | Person card in couple below top | Solid, vertical → horizontal |
| Partner link | Ex/previous partner card center | Main partner card center | Dashed (ex) or solid (previous) |
| Solo drop | Main person card bottom | Solo children row | Solid |

### 9. Z-Index and Layering

The SVG overlay must be above the background but below interactive elements. Currently uses `pointer-events: none` on the SVG and `z-index: 1` on the focused card's `scale-105`.

### 10. Performance

With `FamilyGraph`, tree building uses 0 SQL queries on refocus (cached graph) and 2 queries on data changes. The rendering bottleneck is DOM size — at 3 ancestor generations with full laterals, the tree can have 50+ card elements. LiveView's DOM diffing handles this efficiently since only the cards that change get patched.

---

## Glossary

| Term | Definition |
|------|-----------|
| **Focus person** | The person at the center of the tree view. The tree expands from them. |
| **Couple card** | A UI element showing two partners side-by-side (or one person if no partner). |
| **Pass-through** | An empty placeholder in an ancestor's children row marking where the direct-line child connects to the couple card below. |
| **Direct line** | The lineage path from the focus person straight up through parents, grandparents, etc. |
| **Lateral relative** | A person who is NOT on the direct line but shares an ancestor with the focus person (siblings, uncles, cousins). |
| **Pedigree collapse** | When the same ancestor is reachable through multiple lineage paths (e.g., when cousins marry). |
| **Generation** | A level in the tree. Focus person is generation 0, parents are 1, grandparents are 2, etc. Children are -1, grandchildren -2. |
| **Family unit** | A person + their partners + their children, structured for rendering. |
| **FamilyGraph** | In-memory indexed graph of all people and relationships in a family. Built from 2 SQL queries. |
| **PersonTree** | The recursive data structure produced by `PersonTree.build/3`. Ancestors nest upward, descendants nest downward. |
| **Family group tree** | The render-friendly transformation of PersonTree produced by `to_family_groups/1`. Ancestor trees above, couple card in middle, children below. |
| **Other depth** | Controls how many ancestor levels expand lateral (non-direct-line) children. `other=0` shows only the direct line. `other=1` shows siblings. `other=2` shows cousins. |
| **Union node** | (In DAG layout libraries) A virtual node representing a couple. Parents connect to the union; the union connects to children. |
