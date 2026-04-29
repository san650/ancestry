# Graph Clustering: Sub-Family Visual Layout

## Summary

The graph view (`/org/:org_id/families/:family_id`, `Web.FamilyLive.Show`) currently
lays out each generation row by *insertion order from Phase 1 traversal*, then
centers the row as a single block within the grid. This produces correct
generation alignment but loses sub-family structure — a parent couple is not
visually positioned over its own children, and sibling families merge into a
single undifferentiated row.

This design replaces the layout sub-phase of `Ancestry.People.PersonGraph` with
a **bottom-up subtree-width allocation** algorithm (Walker / Reingold-Tilford
style) so that:

- Each parent couple sits centered above its joint children.
- Sibling families form distinct clusters with separator cells between them.
- Blood-line children sit directly under their parents; spouses anchor on the
  outside of each cluster.
- Asymmetric ancestor depth and pedigree-collapse cases degrade gracefully via
  the existing duplication mechanism.

Phase 1 of the graph build (traversal, dup creation, edge generation) is
**unchanged**. The LiveView template, JS connector hook, and CSS Grid
rendering are **unchanged**. The change is contained to layout column
assignment.

## Problem

Today, `lib/ancestry/people/person_graph.ex` `layout_grid/2` performs:

1. Group entries by generation.
2. For each row, count entries.
3. Center each row's entries within the widest row's count, padding with
   separator cells.

This produces a row like `[A1, A2, A3, B1, B2]` for two sibling families with
3 + 2 children — children appear as a single undifferentiated block centered
under the parents row, with no visual hint that A1/A2/A3 belong to one couple
and B1/B2 to another. Connectors visually cross or compress.

**Goal:** the same family should produce two clusters separated by an empty
column:

```
gen 2:           [Grandpa] [Grandma]
gen 1:  [Adam] [Alice] [   ] [   ] [Bob] [Beth]
gen 0:  [A1]   [A2★]   [A3]  [   ] [B1]  [B2]
```

Spouses (Adam, Beth) anchor the outside of each cluster; blood-line children
(Alice, Bob) sit directly under Grandpa/Grandma; A1–A3 cluster under
(Adam, Alice); B1–B2 cluster under (Bob, Beth); a separator column visually
separates the two sub-families.

## Decisions (validated during brainstorming)

| Decision | Choice | Rationale |
|---|---|---|
| Sub-family clustering | Yes — each parent couple anchors its joint children | Matches user mental model; dramatically improves connector readability |
| Spouse position in sibling cluster | Outside (non-blood-line member on the outer edge) | Keeps blood-line children directly under their grandparents, anchors couple over its own children |
| Ancestor recursion | Parent-A's ancestors on the left, parent-B's on the right, applied at every generation | Standard Sosa-Stradonitz / pedigree-chart layout. Confirmed as the unique crossing-free in-order arrangement for the binary ancestor tree |
| Asymmetric ancestor depth | Collapse the unknown side (Option B). Narrower grid; Father/Mother may shift off-center | User accepts visual concession (Mother may visually line up under Grandma-pat with no connector) in exchange for a compact grid |
| Multi-partner descendant clustering | Hybrid (Option C). Strict alignment for current-partner children; loose lane for ex / previous / solo | Optimizes the 80% case (single current partner) without exploding grid width for blended families |
| Algorithm class | Bottom-up subtree-width allocation (Walker / Reingold-Tilford) | Predictable, recursive, well-documented; naturally produces the agreed v2 mockup |
| Cycle type handling | Reuse existing dup mechanism; layout treats dup stubs as ordinary leaf cells | No special-case algorithm code for Type 1–5; duplication already linearizes cross-gen issues |

## Scope

**In scope:**
- `lib/ancestry/people/person_graph.ex` — replace `layout_grid/2` body with
  a call into the new layout module. Phase 1 (traversal, dup logic,
  `fix_cross_gen_ancestors`, edge generation) untouched.
- New module `lib/ancestry/people/person_graph/layout.ex` — pure functions:
  build family-unit tree, bottom-up width allocation, top-down column
  assignment, separator placement.
- `test/ancestry/people/person_graph_test.exs` — extend with cluster-shape
  assertions for the cycle types and asymmetric-depth scenarios.
- New `test/ancestry/people/person_graph/layout_test.exs` — pure-function unit
  tests on the layout module.

**Out of scope:**
- `Ancestry.People.FamilyGraph` — unchanged.
- Phase 1 of `PersonGraph.build/3` — traversal, dup creation, edges all
  unchanged.
- `lib/web/live/family_live/graph_component.ex` — unchanged. The
  `%PersonGraph{}` public shape (`nodes`, `edges`, `grid_cols`, `grid_rows`)
  is preserved.
- `assets/js/graph_connector.js` — unchanged. Edges still drawn from
  `data-edges`.
- `Ancestry.People.PersonTree` (the indented outline view) — unchanged.

**Non-goals:**
- Pixel-perfect parent centering in all cases.
- Zero edge crossings in adversarial families.
- Handling pathological genealogies. Off-by-a-cell positioning is acceptable
  when constraints conflict.

## Algorithm

### Phase 2A: Build the family-unit tree

Family-unit tree built from the flat `state.entries` and `state.edges` produced
by Phase 1.

**Family unit shape:**

A family unit at generation `N` is one of:

- `%Couple{anchor: {node_a, node_b}, children: [child_unit, ...]}` — 2-cell
  anchor + joint children below.
- `%Single{anchor: node, children: [child_unit, ...]}` — 1-cell anchor (single
  parent, dup stub, or solo-children parent) + children below.
- `%LooseLane{units: [partner_unit, ...]}` — appears only on rows where a
  person has multiple partner groups (focus row, or any descendant row with
  ex / previous / solo + current). The loose lane sits *to the left* of the
  primary couple unit. Children inside the lane do not strictly center over
  the anchor.

A node here is a Phase-1 entry — original or dup. Dup entries have no upward
subtree (handled by Phase 1 already).

**Tree structure:**

The full tree is built in two halves rooted at the focus row:

- **Descendant tree:** rooted at the focus's primary couple unit
  (`(focus, current_partner)` or just `{focus}` if no current partner). Each
  child's subtree is recursively a family unit at the child's generation. Solo
  children of a person and ex / previous / solo group children are wrapped in
  the loose-lane construct.
- **Ancestor tree:** rooted at the focus's parents' couple unit (or single, if
  one parent unknown). For each couple `(A, B)` at generation `N`, the *left
  child* in the family-unit tree is `A`'s parents' couple unit at generation
  `N+1`, and the *right child* is `B`'s parents' couple unit. Lateral siblings
  expanded by `other:` become additional child units of the relevant
  generation's couple unit (alongside the direct-line child).

Dup stubs are leaves: their entry has `duplicated: true` and no upward
traversal in Phase 1, so they appear in the family-unit tree as 1-cell
leaves with no further children/parents.

### Phase 2B: Bottom-up width allocation

A pure recursive walk of the family-unit tree:

- `width(leaf_single) = 1`
- `width(leaf_couple) = 2`
- `width(unit) = max(anchor_width, sum_of_child_widths + cluster_separators)`
  where `anchor_width = 2` for couple, `1` for single.
- **Cluster separators:** between every pair of adjacent sibling sub-family
  units at the same level, insert one separator column. Inside a single
  sibling cluster (e.g., a row of 3 leaves like A1/A2/A3), no inner
  separators.
- **Loose-lane separator:** between the loose lane and the primary couple
  cluster on its right, insert one separator column.
- For asymmetric ancestor depth (Option B): a side with no visible ancestors
  contributes only its own anchor width — *no padding columns reserved
  upward*. So if Mother has no parents shown, gen 2 is sized only by Father's
  lineage; the (Father, Mother) couple at gen 1 sits centered within Father's
  lineage column span.

### Phase 2C: Top-down column assignment

Walk the tree, accumulating `current_col`. For each unit:

1. Compute the cluster's column range: `[start_col, start_col + width - 1]`.
2. Place the anchor at the *center* of the cluster's column range.
   - For a couple anchor: 2 adjacent cells centered (rounded down on odd
     widths so the left member sits at floor-center).
   - For a single anchor: 1 cell at floor-center.
3. Recurse into child units, advancing `current_col` left-to-right; insert
   separator nodes between adjacent units and between cluster boundaries and
   the centered anchor.
4. Lateral siblings: each lateral sibling unit sits next to (typically left
   of) the direct-line child unit, before the separator.

After both halves of the tree (descendant + ancestor) are laid out, **rebase
columns** so the focus row's primary couple cluster aligns with focus's
parents' couple at gen 1 directly above. The ancestor side uses the
focus-couple column position as its bottom anchor; the descendant side uses
it as its top anchor. The grid total `grid_cols` is the union of both halves.

### Phase 2D: Materialize nodes

Convert the placed units back into `%GraphNode{}` and separator nodes:

- Each anchor person → `%GraphNode{type: :person, col: ..., row: ...}` carrying
  the existing entry's `focus`, `duplicated`, `has_more_up`, `has_more_down`.
- Each separator slot in the cluster layout → `%GraphNode{type: :separator,
  id: "sep-#{row}-#{col}", col: ..., row: ...}`.
- Equalizing separators (any unfilled cell in any row, after the cluster
  layout completes) → additional `%GraphNode{type: :separator}` to make every
  cell coordinate present.

### Cycle types and edge cases (free via Phase 1)

| Type | What Phase 1 does | What layout sees |
|---|---|---|
| 1: cousins marry | Reuses C and D as gen-2 siblings (no dup) | One cluster at gen 2 with C, D as leaves under GP+GM |
| 2: woman remarries husband's brother | Reuses Brother-1 as gen-1 sibling and ex-partner | Brother-1 is a leaf at gen 1, sitting on the loose lane next to (Brother-2, Mom) couple |
| 3: double first cousins | Bro-Y-dup + Sis-Y-dup at gen 2 | Three clusters at gen 2 left-to-right: GPA's children (with Bro-X, Bro-Y-original as leaves), the dup couple (Bro-Y-dup, Sis-Y-dup) — its own 2-cell leaf cluster anchoring Parent-2 below — then GPB's children. Two separators between the three. |
| 4: uncle marries niece | Uncle relocated to gen 2 (sibling of Brother), Uncle-dup at gen 1 | Original Uncle is a leaf in GP+GM's sibling cluster at gen 2. Uncle-dup is a leaf in the (Uncle-dup, Niece) couple cluster at gen 1, with Niece's own subtree (Brother+Wife) above. |
| 5: siblings marry into same family | No dup — partner edges not followed upward | Two grandparent clusters at gen 2, with sibling laterals as leaves in each. |

## Testing

### Unit tests (new file: `test/ancestry/people/person_graph/layout_test.exs`)

Pure-function tests on the `Ancestry.People.PersonGraph.Layout` module. Each
feeds a hand-built family-unit tree (or a small flat traversal-output input)
and asserts cluster shape:

| Test | Asserts |
|---|---|
| Single couple, 3 children | Couple column-center == middle child's column. Width(unit) = `max(2, 3) = 3`. |
| Two sibling couples, 3+2 children | Two child clusters (3-wide, 2-wide) with one separator between. Each couple anchor sits over its own children's span. Total width = 3 + 1 + 2 = 6. |
| Asymmetric ancestor depth | Father side: 2 cells at gen 2. Mother side: 0 cells at gen 2. Total gen-2 width = 2. (Father, Mother) couple at gen 1 sits over cols 0–1. |
| Focus with current + ex + solo | Loose-lane (ex partner + ex children) on the left, separator, then primary couple cluster on the right. Current children centered under (focus, current). Ex children centered under ex partner alone. |
| Couple with one dup partner | Couple still 2 cells. Dup leaf contributes no upward subtree; couple's width = couple-side width only. |
| Cluster separator placement | Exactly one separator between adjacent sibling-family clusters; none inside a single family unit. |

### Integration tests (extend `test/ancestry/people/person_graph_test.exs`)

Use the existing seed cycle-type families. Add cluster-shape assertions:

| Test | Asserts |
|---|---|
| Type 1 (cousins marry) | C and D are siblings at gen 2 in the same cluster. One contiguous sibling cluster, no inner separator. |
| Type 3 (double cousins) | Three clusters at gen 2 left-to-right: GPA's children, dup couple (Bro-Y-dup + Sis-Y-dup), GPB's children. Two separators between the three. |
| Type 4 (uncle/niece) | Original Uncle is a leaf in GP+GM's sibling cluster at gen 2 (next to Brother). Uncle-dup at gen 1 is leaf in (Uncle-dup, Niece) couple cluster. |
| Type 5 (siblings same family) | Two grandparent clusters at gen 2, each with siblings as leaves. No dup. |
| Asymmetric depth | Mother contributes no columns above gen 1. (Father, Mother) couple at gen 1 sits centered within Father's lineage; Mother visually lines up under Grandma-pat with no edge connecting them. |

### E2E test (extend `test/user_flows/family_graph_test.exs`)

Smoke test that the rendered grid still works end-to-end:

- Open family show, switch to graph view.
- Assert focus card, focus's parents, and at least one sibling cluster exist
  in the DOM.
- Existing assertions on `test_id("graph-canvas")`, person card click events,
  and depth controls still pass.

E2E does **not** assert visual cluster shape — that is covered at the
unit/integration layer where coordinates are inspectable.

### Acceptance criteria (definition of done)

1. The v2 mockup scenario (Grandparents → Alice & Bob → 3+2 grandchildren)
   produces a grid with two distinct child clusters and a separator between
   A3 and B1.
2. All five cycle types produce the column layouts described above.
3. `mix precommit` passes (compile warnings-as-errors, deps cleanup, format,
   tests).
4. Manual smoke: open a real seeded family in `iex -S mix phx.server`,
   eyeball the graph, confirm the cluster layout matches the v2 mockup.

## Risks and rollout

### Risks

1. **Existing tests assert specific column positions on Phase-1 traversal
   output.** New layout produces different absolute columns. Mitigation:
   update tests to assert *cluster shapes* (relative positions, separator
   placement, anchor-centering) rather than absolute columns.
2. **Wider grid for blended families.** Hybrid (strict-current / loose-rest)
   introduces a separator column between loose lane and primary cluster.
   Mitigation: minimum one separator only; loose lane stays compact.
3. **Asymmetric-depth visual conflict** — Mother lines up under Grandma-pat
   with no edge. Accepted concession of Option B; surfaced in design + one
   inline code comment near the layout entry point.
4. **Performance.** The recursive layout on a 500-person family is single-
   digit milliseconds (one bottom-up pass, one top-down pass). No DB
   changes. Negligible risk.

### Rollout

- Single PR, no feature flag. The change is isolated to `PersonGraph`'s
  layout sub-phase; the public `build/3` API is unchanged.
- Manual visual check before merge; commit message links to before/after
  screenshots.
- Rollback: one-line revert of the layout module call site, restoring the
  previous `layout_grid/2` body.

### Open questions (non-blocking)

- **Cluster gap separator styling.** Today both cluster-gap and equalizing
  separators render with the same dashed border at low opacity. Default: no
  visual change. Revisit after merge if the layout reads as too uniform.
- **Lateral siblings deeper than gen 1** (`other: 2` or higher). Should "just
  work" because each lateral becomes a child of its parent couple unit. If
  weird shapes appear, file a follow-up rather than block this change.

## References

- Source of truth for current behavior: `lib/ancestry/people/person_graph.ex`
- DAG semantics and cycle catalog: `lib/ancestry/people/CLAUDE.md`
- Original DAG grid rendering design: `docs/plans/2026-04-23-dag-grid-rendering-design.md`
- DCG-to-DAG conversion design: `docs/plans/2026-04-22-person-graph-dag-conversion-design.md`
- Walker's algorithm for tree drawing (Walker II, 1990) and Reingold-Tilford
  (1981) — the recursive subtree-width family of layout algorithms this
  design follows.
