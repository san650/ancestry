# Graph Clustering Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Mandatory project skills before each task:** invoke `elixir-phoenix-guide:elixir-essentials` before writing any `.ex` file and `elixir-phoenix-guide:testing-essentials` before writing any `_test.exs` file.

**Goal:** Replace `Ancestry.People.PersonGraph` layout sub-phase (`layout_grid/2`) with a bottom-up subtree-width allocation that produces visually clustered sibling sub-families with parents centered above their joint children.

**Architecture:** A new pure-functional module `Ancestry.People.PersonGraph.Layout` consumes Phase-1 traversal output (`state.entries` + `state.edges` + `focus_id`) and returns the same flat `(nodes, grid_cols, grid_rows)` triple `layout_grid/2` returns today. Internally the module runs four sequential phases — build family-unit tree (2A), bottom-up width allocation (2B), top-down column assignment with two-half rebase (2C), and node materialization (2D). The public `PersonGraph.build/3` API and the `%PersonGraph{}` struct shape are unchanged; the LiveView template, JS connector hook, and CSS Grid renderer are unchanged.

**Tech Stack:** Elixir, Phoenix LiveView, ExUnit. No new dependencies.

**Spec:** `docs/plans/2026-04-28-graph-clustering-design.md`

**Branch:** `cluster-families` (already checked out).

---

## File Structure

### New files

| File | Responsibility |
|---|---|
| `lib/ancestry/people/person_graph/layout.ex` | Pure-functional layout module. Public entry: `Layout.compute/2` that takes `(state, focus_id)` and returns `{nodes, grid_cols, grid_rows}`. Internal struct definitions for family-unit types (Couple / Single / LooseLane). All four sub-phases. |
| `test/ancestry/people/person_graph/layout_test.exs` | Pure-function unit tests. Each test feeds a hand-built family-unit tree (or a tiny flat traversal-output input) and asserts cluster shape — widths, separator placement, anchor centering, rebase math. |

### Modified files

| File | What changes |
|---|---|
| `lib/ancestry/people/person_graph.ex` | Replace the body of `layout_grid/2` with a single call to `Ancestry.People.PersonGraph.Layout.compute/2`. The two pre-layout passes (`fix_has_more_indicators` and `reorder_partners`) move into the new module so traversal output is the only input. |
| `test/ancestry/people/person_graph_test.exs` | Update column-position assertions in existing tests to match the new clustered layout. Add cycle-type cluster-shape tests (Type 1, 3, 4, 5) and an asymmetric-depth test. |
| `test/user_flows/family_graph_test.exs` | Add one E2E smoke test asserting that a Grandparents → Alice & Bob → 3+2 scenario renders a `data-node-id` cell at the expected coordinate for at least one child of each cluster. (No visual cluster assertions — coordinate inspection happens in the unit/integration layer.) |

### Files NOT changed

`FamilyGraph`, `GraphNode`, `GraphEdge`, `PersonTree`, `graph_component.ex`, `graph_connector.js`, `app.css`, the LiveView itself.

---

## Task 1: Scaffold the Layout module with FamilyUnit struct definitions

**Files:**
- Create: `lib/ancestry/people/person_graph/layout.ex`
- Create: `test/ancestry/people/person_graph/layout_test.exs`

This task creates the module skeleton, the three FamilyUnit struct types used internally, and a public `compute/2` that returns an obviously-wrong placeholder. The placeholder lets later tasks be developed TDD-style without boilerplate gymnastics.

- [ ] **Step 1: Write the placeholder test**

```elixir
# test/ancestry/people/person_graph/layout_test.exs
defmodule Ancestry.People.PersonGraph.LayoutTest do
  use ExUnit.Case, async: true

  alias Ancestry.People.PersonGraph.Layout

  describe "compute/2" do
    test "returns an empty triple for an empty state" do
      state = %{entries: %{}, edges: [], visited: %{}, graph: nil, focus_id: nil}
      assert {[], 0, 0} = Layout.compute(state, nil)
    end
  end
end
```

- [ ] **Step 2: Run the test — verify compile failure**

Run: `mix test test/ancestry/people/person_graph/layout_test.exs`
Expected: `(CompileError) module Ancestry.People.PersonGraph.Layout is not loaded`.

- [ ] **Step 3: Implement the skeleton module**

```elixir
# lib/ancestry/people/person_graph/layout.ex
defmodule Ancestry.People.PersonGraph.Layout do
  @moduledoc """
  Bottom-up subtree-width allocation layout for `PersonGraph`.

  Consumes Phase-1 traversal output (entries grouped by generation + edges +
  focus_id) and produces a flat `(nodes, grid_cols, grid_rows)` triple ready
  to be returned from `PersonGraph.build/3`.

  See `docs/plans/2026-04-28-graph-clustering-design.md` for the algorithm.
  """

  alias Ancestry.People.GraphNode

  defmodule Couple do
    @moduledoc false
    defstruct [:anchor_a, :anchor_b, children: []]
  end

  defmodule Single do
    @moduledoc false
    defstruct [:anchor, children: []]
  end

  defmodule LooseLane do
    @moduledoc false
    defstruct units: []
  end

  @doc """
  Computes the layout for the given Phase-1 state.

  Returns `{nodes, grid_cols, grid_rows}` where `nodes` is a flat list of
  `%GraphNode{}` cells (persons + separators), `grid_cols` is the maximum
  column count, and `grid_rows` is `max_gen - min_gen + 1`.
  """
  def compute(%{entries: entries} = _state, _focus_id) when map_size(entries) == 0 do
    {[], 0, 0}
  end

  def compute(_state, _focus_id) do
    # Real implementation arrives in Tasks 2-7.
    {[], 0, 0}
  end
end
```

- [ ] **Step 4: Run the test — verify it passes**

Run: `mix test test/ancestry/people/person_graph/layout_test.exs`
Expected: 1 test, 0 failures.

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/people/person_graph/layout.ex test/ancestry/people/person_graph/layout_test.exs
git commit -m "Scaffold PersonGraph.Layout module with FamilyUnit struct types"
```

---

## Task 2: Phase 2A — build the descendant family-unit tree

**Files:**
- Modify: `lib/ancestry/people/person_graph/layout.ex`
- Modify: `test/ancestry/people/person_graph/layout_test.exs`

Add a private function `build_descendant_tree(state, focus_id)` that walks Phase-1's `entries` map (gen ≤ 0) and produces a `%Couple{}` rooted at the focus's primary couple unit, with `%LooseLane{}` wrapping ex/previous/solo partner groups on the left.

- [ ] **Step 1: Write tests for descendant tree shape**

Use a hand-built Phase-1-shape state. Helper: a `make_entry/1` helper at the bottom of the test file that returns the same shape `add_entry/6` produces in `PersonGraph` (a map with `:person`, `:gen`, `:duplicated`, `:has_more_up`, `:has_more_down`, `:focus`).

```elixir
describe "build_descendant_tree/2 (via compute)" do
  test "single couple with three children produces one couple unit" do
    focus = make_person(1, "Focus")
    partner = make_person(2, "Partner")
    [c1, c2, c3] = [make_person(3, "C1"), make_person(4, "C2"), make_person(5, "C3")]

    state =
      %{}
      |> add_entry_helper(focus, 0, focus: true)
      |> add_entry_helper(partner, 0)
      |> add_entry_helper(c1, -1)
      |> add_entry_helper(c2, -1)
      |> add_entry_helper(c3, -1)
      |> add_couple_edge(focus.id, partner.id, "married")
      |> add_parent_child_edge(focus.id, c1.id)
      |> add_parent_child_edge(focus.id, c2.id)
      |> add_parent_child_edge(focus.id, c3.id)
      |> add_parent_child_edge(partner.id, c1.id)
      |> add_parent_child_edge(partner.id, c2.id)
      |> add_parent_child_edge(partner.id, c3.id)

    tree = Layout.__build_descendant_tree__(state, focus.id)

    assert %Layout.Couple{anchor_a: a, anchor_b: b, children: kids} = tree
    assert a.person.id == focus.id
    assert b.person.id == partner.id
    assert Enum.map(kids, & &1.anchor.person.id) == [c1.id, c2.id, c3.id]
  end

  test "ex partner with children sits in a LooseLane to the left" do
    # focus has ex-wife and current-wife
    # ex_kid is child with ex; cur_kid is child with current
    # Expected: %Couple{ children = [ %LooseLane{ units = [%Single{ex_partner, [ex_kid_unit]}] }, %Couple{focus, current, [cur_kid_unit]} ] }
    # Structure detail TBD by implementation; the assertion checks ex_kid sits inside a LooseLane.
  end

  test "duplicated child is a leaf with no further descent" do
    # Build a state where one child has duplicated: true.
    # Assert the tree contains a Single (or Couple with dup leaf) and no recursion below.
  end
end

# helpers at bottom of file — minimum needed shape for the algorithm
defp make_person(id, name), do: %{id: id, given_name: name}
defp add_entry_helper(state, person, gen, opts \\ [])
defp add_couple_edge(state, a_id, b_id, rel_kind)
defp add_parent_child_edge(state, parent_id, child_id)
```

> **Note:** The exact helper signatures depend on the existing test file conventions. Read `lib/ancestry/people/person_graph.ex` `add_entry/6`, `add_parent_child_edge/4`, and `add_couple_edge/7` to mirror the entry/edge shapes exactly.

> **Internal API surface:** Use `Layout.__build_descendant_tree__/2` as a deliberately-mangled name to expose the internal function for tests without polluting the module's public API. Public callers only use `Layout.compute/2`.

- [ ] **Step 2: Run tests — verify they fail**

Run: `mix test test/ancestry/people/person_graph/layout_test.exs`
Expected: failures because `__build_descendant_tree__/2` doesn't exist yet.

- [ ] **Step 3: Implement Phase 2A descendant side**

Read `Ancestry.People.PersonGraph` (specifically `traverse_descendants/5`) — the new function reproduces the same partner-grouping logic but emits family-unit structs instead of flat entries.

```elixir
# Inside lib/ancestry/people/person_graph/layout.ex

@doc false
def __build_descendant_tree__(state, focus_id) do
  build_descendant_unit(focus_id, 0, state)
end

defp build_descendant_unit(person_id, gen, state) do
  # 1. Find all entries at `gen` whose person.id == person_id (original, not dup).
  # 2. Find all couple edges where person_id is one endpoint at `gen`.
  # 3. Group into [ex_partners, previous_partners, current_partner].
  # 4. For each non-current partner with children, wrap in %Single{} pointing at
  #    that partner alone with their children's units below.
  # 5. Wrap all non-current partner units in %LooseLane{units: [...]} (or omit if empty).
  # 6. Build the primary anchor:
  #    - If current partner exists: %Couple{anchor_a: person_entry, anchor_b: partner_entry,
  #      children: [child_units]}
  #    - Otherwise: %Single{anchor: person_entry, children: [child_units]}
  # 7. The primary anchor's `children` is built by recursively calling
  #    build_descendant_unit/3 for each child whose parents are (person, current_partner)
  #    and the solo children of `person`.
  # 8. Return either the primary anchor directly (if no loose lane) or a wrapper that
  #    keeps the loose lane to the left of the primary in a parent's `children` list.

  # Implementation detail: the wrapping of LooseLane only applies at the focus's
  # primary anchor — when descending into a child, that child's own multi-partner
  # situation gets its own LooseLane in the SAME WAY. So this function is
  # recursive: each call may produce a Couple/Single with its own LooseLane to
  # the left of the primary.
end
```

The implementation will need helpers:
- `partners_for/3` — given `state`, `person_id`, `gen`, returns `[{partner_entry, rel_kind, group_kind}]` where `group_kind ∈ [:ex, :previous, :current]`.
- `children_of_pair/4` — list of child entries at `gen - 1` whose parents are `{person_id, partner_id}`.
- `solo_children_of/3` — child entries whose only parent in the graph is `person_id`.

These are the same lookups Phase 1 uses, but driven by `state.edges` rather than the upstream `FamilyGraph` (so the layout is fully decoupled from `FamilyGraph`).

- [ ] **Step 4: Run tests until passing**

Run: `mix test test/ancestry/people/person_graph/layout_test.exs`
Iterate until all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/people/person_graph/layout.ex test/ancestry/people/person_graph/layout_test.exs
git commit -m "Phase 2A descendant: build family-unit tree from traversal entries"
```

---

## Task 3: Phase 2A — build the ancestor family-unit tree (including laterals)

**Files:**
- Modify: `lib/ancestry/people/person_graph/layout.ex`
- Modify: `test/ancestry/people/person_graph/layout_test.exs`

Add `__build_ancestor_tree__(state, focus_id)`. Walk gen ≥ 1 entries upward from focus. For each couple at gen N, the left subtree is parent-A's parents' couple unit at gen N+1; the right subtree is parent-B's parents'. Lateral siblings (entries at gen N that share a parent couple but are not on the focus's direct line) become additional children of their parent couple unit, **on the outside** of the direct-line child (left for left-side parent, right for right-side parent).

- [ ] **Step 1: Write tests for ancestor tree shape**

```elixir
describe "build_ancestor_tree/2 (via compute)" do
  test "two-generation symmetric ancestors" do
    # Focus's parents: Father, Mother. Grandparents on each side.
    # Assert tree is:
    # %Couple{
    #   anchor_a: <Father>, anchor_b: <Mother>,
    #   children: [
    #     %Couple{anchor_a: <Grandpa-pat>, anchor_b: <Grandma-pat>, children: []}, # Father's parents
    #     %Couple{anchor_a: <Grandpa-mat>, anchor_b: <Grandma-mat>, children: []}  # Mother's parents
    #   ]
    # }
  end

  test "asymmetric depth — only Father has parents" do
    # Mother's parents are not in entries.
    # Assert:
    # %Couple{anchor_a: <Father>, anchor_b: <Mother>, children: [<Father's parents couple>]}
    # Mother contributes no upward subtree.
  end

  test "lateral sibling sits on the outside of the direct-line child" do
    # Focus's father has a sibling (uncle). The grandparents are at gen 2.
    # Assert:
    # %Couple{Grandpa-pat, Grandma-pat, children: [<Uncle Single>, <Father couple unit>]}
    # — Uncle on the LEFT of Father (Father is left-side parent of focus).
    # And Mother's side: any lateral aunt sits on the RIGHT of Mother.
  end

  test "duplicated parent is a leaf — no upward subtree" do
    # When fix_cross_gen_ancestors created an Uncle-dup at gen 1, the dup
    # entry has duplicated: true. The ancestor walk should NOT recurse above
    # a dup. Assert the dup appears as a leaf (anchor only, children empty).
  end
end
```

- [ ] **Step 2: Run tests — verify they fail**

Run: `mix test test/ancestry/people/person_graph/layout_test.exs`
Expected: failures because `__build_ancestor_tree__/2` doesn't exist.

- [ ] **Step 3: Implement Phase 2A ancestor side**

```elixir
@doc false
def __build_ancestor_tree__(state, focus_id) do
  # 1. Find focus's parents at gen 1 by reading parent_child edges where
  #    to_id == "person-#{focus_id}". Each parent's entry is at gen 1 in
  #    state.entries.
  # 2. Build the focus's parents' couple unit: %Couple{anchor_a, anchor_b, children: []}
  #    where children come from step 4.
  # 3. For each parent, recurse upward via build_ancestor_unit/3.
  # 4. The recursive function returns a %Couple{} (or %Single{}) for the parent's
  #    parents at gen+1, with children = parent's parents' parents (gen+2), etc.
  # 5. Lateral siblings: when building the parents' couple at gen N, look up
  #    children of (anchor_a, anchor_b) at gen N-1 OTHER THAN the direct-line
  #    descendant. Those become %Single{} or %Couple{} (if married) leaf-or-
  #    subtree units.
  # 6. Lateral placement (in the children list of the parent couple): laterals
  #    of the LEFT-SIDE parent's couple go BEFORE the direct-line child;
  #    laterals of the RIGHT-SIDE parent's couple go AFTER.
end
```

Helpers reuse those from Task 2 plus a new `parents_of/3` that reads `state.edges` to find parent-child edges pointing to a given person.

- [ ] **Step 4: Run tests until passing**

Run: `mix test test/ancestry/people/person_graph/layout_test.exs`
Iterate.

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/people/person_graph/layout.ex test/ancestry/people/person_graph/layout_test.exs
git commit -m "Phase 2A ancestor: build recursive ancestor tree with lateral siblings"
```

---

## Task 4: Phase 2B — bottom-up width allocation

**Files:**
- Modify: `lib/ancestry/people/person_graph/layout.ex`
- Modify: `test/ancestry/people/person_graph/layout_test.exs`

A pure recursive walk computing `width(unit)` for every unit. The width includes cluster separators between adjacent sibling sub-family units and between a loose lane and the primary unit on its right.

- [ ] **Step 1: Write tests for widths**

```elixir
describe "width/1" do
  test "leaf single is 1" do
    leaf = %Layout.Single{anchor: %{person: %{id: 1}}, children: []}
    assert Layout.__width__(leaf) == 1
  end

  test "leaf couple is 2" do
    leaf = %Layout.Couple{anchor_a: %{person: %{id: 1}}, anchor_b: %{person: %{id: 2}}, children: []}
    assert Layout.__width__(leaf) == 2
  end

  test "couple with three child leaves: max(2, 3) = 3" do
    couple = %Layout.Couple{
      anchor_a: a, anchor_b: b,
      children: [s1, s2, s3]  # three Single leaves
    }
    assert Layout.__width__(couple) == 3
  end

  test "two sibling couples 3+2 = 6 (3 + 1 separator + 2)" do
    parent = %Layout.Couple{
      anchor_a: gp_a, anchor_b: gp_b,
      children: [
        %Layout.Couple{anchor_a: a1, anchor_b: a2, children: [c, c, c]},  # width 3
        %Layout.Couple{anchor_a: b1, anchor_b: b2, children: [c, c]}      # width 2
      ]
    }
    # parent's children: 3 + 1 (separator) + 2 = 6
    # parent's anchor: 2
    # parent's width: max(2, 6) = 6
    assert Layout.__width__(parent) == 6
  end

  test "loose lane width includes separator before primary" do
    # %Couple{anchor_a, anchor_b, children: [%LooseLane{units: [%Single{...}]}, primary_couple]}
    # children width = LooseLane width + 1 separator + primary_couple width
  end

  test "asymmetric ancestor: missing side contributes anchor only" do
    # %Couple{father, mother, children: [father_grandparents_couple]}
    # children width = 2 (father's parents); no padding for mother's missing side
    # parent width = max(anchor 2, 2) = 2
  end
end
```

- [ ] **Step 2: Run tests — verify they fail**

- [ ] **Step 3: Implement `__width__/1`**

```elixir
@doc false
def __width__(%Single{children: []}), do: 1
def __width__(%Couple{children: []}), do: 2

def __width__(%Single{children: kids}),
  do: max(1, children_width(kids))

def __width__(%Couple{children: kids}),
  do: max(2, children_width(kids))

def __width__(%LooseLane{units: units}) do
  # loose-lane width = sum of unit widths + (n - 1) separators
  case units do
    [] -> 0
    [u] -> __width__(u)
    [_ | _] -> Enum.sum(Enum.map(units, &__width__/1)) + length(units) - 1
  end
end

# children_width handles the LooseLane-then-primary case:
# - If a child is a LooseLane, add its width + 1 separator after it.
# - Between any two consecutive sibling units, add 1 separator.
defp children_width([]), do: 0
defp children_width([only]), do: __width__(only)
defp children_width([first | rest]) do
  __width__(first) + 1 + children_width(rest)
end
```

- [ ] **Step 4: Run tests until passing**

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/people/person_graph/layout.ex test/ancestry/people/person_graph/layout_test.exs
git commit -m "Phase 2B: bottom-up width allocation with cluster separators"
```

---

## Task 5: Phase 2C — top-down column assignment within a single half

**Files:**
- Modify: `lib/ancestry/people/person_graph/layout.ex`
- Modify: `test/ancestry/people/person_graph/layout_test.exs`

Walk the tree top-down accumulating `current_col`. Each unit is given a column range `[start_col, start_col + width - 1]`. Within that range, the anchor sits at the floor-center; children advance left-to-right with one separator between siblings. Output: a flat list `[{:placed, %Couple{}, anchor_cols, row} | {:separator, col, row}]` ready for Task 6 to merge across halves.

- [ ] **Step 1: Write tests for column assignment**

```elixir
describe "place_half/3" do
  test "couple over three children: anchor at cols [1, 2]; kids at [0, 1, 2]" do
    tree = %Layout.Couple{
      anchor_a: dad, anchor_b: mom,
      children: [
        %Layout.Single{anchor: c1, children: []},
        %Layout.Single{anchor: c2, children: []},
        %Layout.Single{anchor: c3, children: []}
      ]
    }

    placements = Layout.__place_half__(tree, 0, :descendant)

    # The couple anchor is on row R; children on row R+1
    # cols: dad at 1, mom at 2, c1 at 0, c2 at 1, c3 at 2
    # plus separators implicit
    assert anchor_col(placements, dad) == 1
    assert anchor_col(placements, mom) == 2
    assert anchor_col(placements, c1) == 0
    assert anchor_col(placements, c2) == 1
    assert anchor_col(placements, c3) == 2
  end

  test "two sibling couples (3+2): cluster A at cols 0-2, separator at 3, cluster B at 4-5" do
    # Outer parent couple over the two sibling couples.
    # Assert positions for all anchors and the separator at col 3.
  end

  test "loose lane on the left of primary couple" do
    # ex partner with 1 ex-child; primary couple with 2 current-children.
    # Expected order: [ex_partner, ex_child] separator [focus, current, c1, c2]
    # Assert exact column positions.
  end

  test "lateral sibling on the outside of the direct-line child" do
    # Father has a sibling (Uncle) at gen 1. Mother has no laterals.
    # Grandparents at gen 2 over [Uncle, Father], with Father on the right.
    # Expected: Uncle at col 0, Father at col 1, Mother at col 2 (loose lane separator?)
  end
end
```

- [ ] **Step 2: Run tests — verify they fail**

- [ ] **Step 3: Implement `__place_half__/3`**

```elixir
@doc false
def __place_half__(unit, base_row, direction) do
  # direction: :descendant (children below = row + 1) or :ancestor (parents above = row - 1)
  width = __width__(unit)
  do_place(unit, 0, base_row, width, direction, [])
end

defp do_place(%Single{anchor: a, children: kids}, start_col, row, width, dir, acc) do
  anchor_col = start_col + div(width - 1, 2)
  acc = [{:placed_anchor, a, anchor_col, row} | acc]
  place_children(kids, start_col, child_row(row, dir), dir, acc)
end

defp do_place(%Couple{anchor_a: a, anchor_b: b, children: kids}, start_col, row, width, dir, acc) do
  anchor_a_col = start_col + div(width - 2, 2)
  anchor_b_col = anchor_a_col + 1
  acc = [{:placed_anchor, a, anchor_a_col, row}, {:placed_anchor, b, anchor_b_col, row} | acc]
  place_children(kids, start_col, child_row(row, dir), dir, acc)
end

defp do_place(%LooseLane{units: units}, start_col, row, _width, dir, acc) do
  # lay each unit out left-to-right, separator between
  place_units_in_row(units, start_col, row, dir, acc)
end

defp child_row(row, :descendant), do: row + 1
defp child_row(row, :ancestor), do: row - 1
```

The implementation needs `place_children/5` and `place_units_in_row/5`, both of which advance `current_col` left-to-right, recursing into each unit and inserting `{:separator, col, row}` placements between adjacent units.

- [ ] **Step 4: Run tests until passing**

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/people/person_graph/layout.ex test/ancestry/people/person_graph/layout_test.exs
git commit -m "Phase 2C: top-down column assignment within a single half"
```

---

## Task 6: Phase 2C — rebase + merge two halves

**Files:**
- Modify: `lib/ancestry/people/person_graph/layout.ex`
- Modify: `test/ancestry/people/person_graph/layout_test.exs`

Compute `delta` from the descendant's primary couple position vs the ancestor's parent couple position. Apply shift to both halves so the seam aligns. Handle the negative-shift fallback (shift descendants right instead).

- [ ] **Step 1: Write tests for rebase**

```elixir
describe "merge_halves/3" do
  test "positive shift: focus at cols [8, 9], Wa=4, Wb=6 → ancestor parent couple lands at [8, 9]" do
    # Use the worked example from the design spec
  end

  test "negative shift: focus at cols [1, 2], Wa=4 → descendants shift right by 2" do
    # Use the negative-shift example from the design spec
  end

  test "asymmetric depth: Mother has no parents → ancestor tree is just Father's lineage + couple" do
    # With Wb=0, ancestor tree's Father is at local col Wa-1, Mother at Wa.
    # Rebase aligns Father with focus's column.
  end

  test "no descendants: focus at cols [0, 1], ancestor tree starts at col 0" do
    # When focus has no descendants (descendant tree just contains focus and partners),
    # ancestor tree pins to col 0 directly.
  end
end
```

- [ ] **Step 2: Run tests — verify they fail**

- [ ] **Step 3: Implement `__merge_halves__/2`**

```elixir
@doc false
def __merge_halves__(descendant_placements, ancestor_placements) do
  desc_focus_col = focus_couple_left_col(descendant_placements)
  anc_parent_left_col = parent_couple_left_col(ancestor_placements)

  delta = desc_focus_col - anc_parent_left_col

  {desc_shift, anc_shift} =
    if delta < 0 do
      # Negative shift: shift descendants right by -delta, ancestors stay
      {-delta, 0}
    else
      {0, delta}
    end

  shifted_desc = Enum.map(descendant_placements, &shift_col(&1, desc_shift))
  shifted_anc = Enum.map(ancestor_placements, &shift_col(&1, anc_shift))

  shifted_desc ++ shifted_anc
end
```

- [ ] **Step 4: Run tests until passing**

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/people/person_graph/layout.ex test/ancestry/people/person_graph/layout_test.exs
git commit -m "Phase 2C: rebase and merge descendant + ancestor halves"
```

---

## Task 7: Phase 2D — materialize nodes, normalize rows, fill equalizers

**Files:**
- Modify: `lib/ancestry/people/person_graph/layout.ex`
- Modify: `test/ancestry/people/person_graph/layout_test.exs`

Convert merged placements into a flat `[%GraphNode{}]`. Compute `grid_cols` (max col + 1) and `grid_rows` (max row - min row + 1). Normalize all rows so the highest ancestor row = 0. Fill any unfilled `(row, col)` cell with a separator GraphNode.

- [ ] **Step 1: Write the integrating test**

```elixir
test "compute/2 end-to-end: simple Grandparents → Alice & Bob → 3+2 grandchildren" do
  # Build a Phase-1 state matching the v2 mockup.
  # Assert the resulting nodes:
  # - grid_cols = 7 or 8 (depends on separator count)
  # - grid_rows = 3
  # - Alice and Bob at row 1, in columns directly under Grandpa/Grandma at row 0
  # - A1, A2, A3 at row 2 cols [0, 1, 2]; separator at col 3; B1, B2 at row 2 cols [4, 5]
end
```

- [ ] **Step 2: Run test — verify it fails**

- [ ] **Step 3: Implement `compute/2`'s real body**

```elixir
def compute(state, focus_id) do
  desc_tree = __build_descendant_tree__(state, focus_id)
  anc_tree  = __build_ancestor_tree__(state, focus_id)

  desc_placements = if desc_tree, do: __place_half__(desc_tree, 0, :descendant), else: []
  anc_placements  = if anc_tree,  do: __place_half__(anc_tree,  0, :ancestor),  else: []

  merged = __merge_halves__(desc_placements, anc_placements)
  {nodes, cols, rows} = __materialize__(merged)
  {nodes, cols, rows}
end

@doc false
def __materialize__(placements) do
  # 1. Normalize rows: shift so min_row = 0
  # 2. Compute grid_cols, grid_rows
  # 3. Convert placements into %GraphNode{type: :person} or %GraphNode{type: :separator}
  # 4. Fill every unfilled (row, col) with a separator node
  # 5. Return {nodes, grid_cols, grid_rows}
end
```

The `:placed_anchor` placements carry the original entry which already has `focus`, `duplicated`, `has_more_up`, `has_more_down`, and `person`. Each becomes:

```elixir
%GraphNode{
  id: if(entry.duplicated, do: "person-#{entry.person.id}-dup", else: "person-#{entry.person.id}"),
  type: :person,
  col: col,
  row: row_normalized,
  person: entry.person,
  focus: entry.focus,
  duplicated: entry.duplicated,
  has_more_up: entry.has_more_up,
  has_more_down: entry.has_more_down
}
```

Separator placements become:

```elixir
%GraphNode{
  id: "sep-#{row_normalized}-#{col}",
  type: :separator,
  col: col,
  row: row_normalized
}
```

After processing all explicit placements, sweep the `grid_cols × grid_rows` rectangle and add `%GraphNode{type: :separator}` for every cell coordinate not already covered.

- [ ] **Step 4: Run tests until passing**

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/people/person_graph/layout.ex test/ancestry/people/person_graph/layout_test.exs
git commit -m "Phase 2D: materialize nodes, normalize rows, fill equalizing separators"
```

---

## Task 8: Wire Layout into PersonGraph and update existing tests

**Files:**
- Modify: `lib/ancestry/people/person_graph.ex`
- Modify: `test/ancestry/people/person_graph_test.exs`

Replace `layout_grid/2`'s body with one call to `Layout.compute/2`. Move `fix_has_more_indicators/2` and `reorder_partners/2` into `Layout` (or call them from inside `compute/2`). Update existing PersonGraph tests that asserted absolute column positions.

- [ ] **Step 1: Read existing PersonGraph tests to identify column-position assertions**

Run: `grep -n "col:" test/ancestry/people/person_graph_test.exs`
Read each match. Tests that assert specific `col` values on focus, parents, children will likely need updating.

- [ ] **Step 2: Replace layout_grid/2's body**

```elixir
# lib/ancestry/people/person_graph.ex

defp layout_grid(state, focus_id) do
  Ancestry.People.PersonGraph.Layout.compute(state, focus_id)
end
```

Move `fix_has_more_indicators/2` and `reorder_partners/2` into `Layout` (called from inside `compute/2` as the first thing). Drop `make_node_id/4`, `extract_person_id/1`, `build_partner_map/1`, `reorder_generation/2`, `find_partner_entries/4`, `rebuild_generation/4`, `reinsert_separators/2`, `build_partner_groups/4` if they're now unused. Verify with `mix compile --warnings-as-errors`.

- [ ] **Step 3: Update existing PersonGraph tests**

For each test that asserts on absolute `col` values:
- If the test is asserting the *shape* (focus is on row N, has K parents on row N-1), keep the row assertion and replace col-specific assertions with relative checks (`focus_col == middle of parents` or `parent_a.col + 1 == parent_b.col`).
- If the test is asserting on cluster shapes (e.g., all kids on the same row), keep as-is.

- [ ] **Step 4: Run the full PersonGraph test suite**

Run: `mix test test/ancestry/people/`
Iterate until all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/people/person_graph.ex test/ancestry/people/person_graph_test.exs
git commit -m "Wire PersonGraph.layout_grid through new Layout module"
```

---

## Task 9: Add cycle-type and asymmetric-depth integration tests

**Files:**
- Modify: `test/ancestry/people/person_graph_test.exs`

Use the existing `seeds_test_cycles.exs` fixtures (already used in current cycle-type tests). Add cluster-shape assertions for Type 1, 3, 4, 5 and a new asymmetric-depth test.

- [ ] **Step 1: Add Type 1 cluster-shape test**

```elixir
test "Type 1 cousins marry — C and D appear once each as siblings" do
  # Use the Intermarried Clans seed family, focus = Zara
  # Assert at gen 2: a single contiguous sibling cluster containing
  # both C and D under GP+GM (no inner separator between them).
end
```

- [ ] **Step 2: Add Type 3 cluster-shape test**

```elixir
test "Type 3 double cousins — three clusters at gen 2 with two separators" do
  # focus = Quentin (Intermarried Clans)
  # Assert at gen 2 left-to-right: GPA's children cluster, then dup couple
  # (Bro-Y-dup + Sis-Y-dup) as a 2-cell cluster, then GPB's children
  # cluster. Two separator cells between the three.
end
```

- [ ] **Step 3: Add Type 4 cluster-shape test**

```elixir
test "Type 4 uncle marries niece — Uncle leaf at gen 2, Uncle-dup leaf at gen 1" do
  # focus = Felix (Intermarried Clans)
  # Assert original Uncle is in GP+GM's sibling cluster at gen 2.
  # Assert Uncle-dup at gen 1 is paired with Niece in the (Uncle-dup, Niece)
  # couple, with Niece's own subtree (Brother+Wife) above her.
end
```

- [ ] **Step 4: Add Type 5 cluster-shape test**

```elixir
test "Type 5 siblings same family — two grandparent clusters, no dups" do
  # focus = Noreen (Intermarried Clans)
  # Assert dup_count(graph) == 0 and two grandparent clusters at gen 2.
end
```

- [ ] **Step 5: Add asymmetric-depth test**

```elixir
test "Father 2-deep, Mother 0-deep — Mother lines up under Grandma-pat with no edge" do
  # Build a small family with Father's parents but Mother's parents unknown.
  # Assert Mother's column == Grandma-pat's column.
  # Assert NO parent_child edge from Grandma-pat to Mother.
end
```

- [ ] **Step 6: Run integration tests**

Run: `mix test test/ancestry/people/person_graph_test.exs`
Iterate until all pass.

- [ ] **Step 7: Commit**

```bash
git add test/ancestry/people/person_graph_test.exs
git commit -m "Add cluster-shape integration tests for cycle types and asymmetric depth"
```

---

## Task 10: E2E smoke test

**Files:**
- Modify: `test/user_flows/family_graph_test.exs`

One smoke test verifying the v2 mockup scenario renders without errors and shows distinct sibling clusters.

- [ ] **Step 1: Add the E2E test**

```elixir
# Sub-family clusters render correctly
#
# Given a family with Grandpa+Grandma → Alice and Bob, where
#   Alice + Adam have 3 children (A1, A2, A3) and
#   Bob + Beth have 2 children (B1, B2),
# When the user navigates to the family show page focused on A2,
# Then the graph canvas renders.
# And A1, A2, A3 cards are present in the same row.
# And B1, B2 cards are present in the same row.
# And A2 has data-focus="true".
test "sub-family clusters render correctly", %{conn: conn} do
  # Set up the scenario using `insert/2` factories.
  # Visit `/org/:org_id/families/:family_id?person_id=#{a2.id}`.
  # Assert presence of all 5 grandchildren by data-node-id.
  # Assert A2's card has data-focus="true".
end
```

- [ ] **Step 2: Run the E2E test**

Run: `mix test test/user_flows/family_graph_test.exs --trace`
Iterate until passing.

- [ ] **Step 3: Commit**

```bash
git add test/user_flows/family_graph_test.exs
git commit -m "Add E2E smoke test for sub-family cluster rendering"
```

---

## Task 11: Manual smoke + precommit

**Files:** none (but check the dev server visually)

- [ ] **Step 1: Run mix precommit**

Run: `mix precommit`
This runs compile-with-warnings-as-errors, deps cleanup, format, and the full test suite.

- [ ] **Step 2: Fix any issues**

If anything fails, fix and re-run.

- [ ] **Step 3: Manual visual check**

Run: `iex -S mix phx.server`
Open `http://localhost:4000/`, log in, navigate to a seeded family with the Intermarried Clans data (or a multi-sibling family). Switch to graph view. Confirm:
- Sibling sub-families form distinct clusters with separator gaps between them.
- Each parent couple sits centered above its joint children.
- Focus person is highlighted and scrolled into view.
- Re-centering on a different person rebuilds the graph correctly.
- Depth controls still work.

If the visual looks off, file a follow-up issue rather than block this change — the algorithm matches the spec, the visual judgement is a separate iteration.

- [ ] **Step 4: Final commit / PR**

```bash
git push -u origin cluster-families
gh pr create --title "Sub-family graph clustering" --body "$(cat <<'EOF'
## Summary

- Replaces PersonGraph's `layout_grid/2` body with a bottom-up subtree-width allocation.
- Each parent couple now sits centered above its joint children.
- Sibling sub-families form distinct visual clusters with separator gaps.
- Phase 1 (traversal, dup creation, edges) and the rendering layer (LiveView, JS connector hook, CSS Grid) are unchanged.

Spec: `docs/plans/2026-04-28-graph-clustering-design.md`

## Test plan

- [ ] `mix precommit` passes
- [ ] Manually verify the v2 mockup scenario renders with two distinct child clusters
- [ ] Verify cycle types Type 1, 3, 4, 5 still render correctly
- [ ] Verify the focus highlight and scroll-to-focus still work
EOF
)"
```

---

## Implementation Notes

### Mandatory skills

- Before writing any `.ex` file: invoke `elixir-phoenix-guide:elixir-essentials`.
- Before writing any `_test.exs` file: invoke `elixir-phoenix-guide:testing-essentials`.

### Code style hints (per project CLAUDE.md)

- Use `pgettext/2` for any new gendered translatable strings (none expected in this change, but if any error message needs i18n, use `gettext`).
- Use `Tidewave` MCP tools to verify schema fields, function arities, and runtime behavior before assuming.
- This change touches no DB tables, no migrations.

### Reference

- Spec: `docs/plans/2026-04-28-graph-clustering-design.md`
- Existing layout (the code being replaced): `lib/ancestry/people/person_graph.ex` `layout_grid/2` and helpers.
- Existing Phase 1 (unchanged): `lib/ancestry/people/person_graph.ex` `traverse_ancestors/5`, `traverse_descendants/5`, `traverse_laterals/4`, `fix_cross_gen_ancestors/2`.
- Cycle-type catalog: `lib/ancestry/people/CLAUDE.md`.
- Test conventions: `test/CLAUDE.md` and `test/user_flows/CLAUDE.md`.
- Learnings to apply: `docs/learnings.jsonl` — grep for `morphdom`, `at-limit`.
