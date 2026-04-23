# PersonGraph Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `PersonTree` with `PersonGraph`, adding cycle detection via a visited-map accumulator, configurable depth controls, and "(duplicated)" stub cards.

**Architecture:** Thread a `%{person_id => generation}` visited map through every recursive call in the tree builder. When a person is already in the map, emit a stub with `duplicated: true` instead of recursing. Depth probe at the focus person's level sorts parents deeper-first. Generation numbers are renumbered from focus-relative to top-down before returning.

**Tech Stack:** Elixir, `Ancestry.People.FamilyGraph` (unchanged), `Web.FamilyLive.PersonCardComponent` (rendering updates)

**Spec:** `docs/plans/2026-04-22-person-graph-dag-conversion-design.md`

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Rename | `lib/ancestry/people/person_tree.ex` → `lib/ancestry/people/person_graph.ex` | Module rename + full rewrite of build algorithm |
| Rename | `test/ancestry/people/person_tree_test.exs` → `test/ancestry/people/person_graph_test.exs` | All PersonGraph tests (existing + new cycle/depth tests) |
| Modify | `lib/web/live/family_live/show.ex` (lines 13, 98, 181, 613) | Update alias and 3 call sites from `PersonTree` → `PersonGraph` |
| Modify | `lib/web/live/family_live/show.ex` (line 578) | Update `count_parents` to handle new person entry shape |
| Modify | `lib/web/live/family_live/person_card_component.ex` | Update `person_card`, `couple_card`, `ancestor_subtree` to handle `%{person: ..., duplicated: ...}` shape |
| Modify | `lib/web/live/family_live/show.html.heex` (line 180-195) | Update ancestor rendering for new person entry shape |

---

### Task 1: Rename PersonTree → PersonGraph (module, file, references)

**Files:**
- Rename: `lib/ancestry/people/person_tree.ex` → `lib/ancestry/people/person_graph.ex`
- Rename: `test/ancestry/people/person_tree_test.exs` → `test/ancestry/people/person_graph_test.exs`
- Modify: `lib/web/live/family_live/show.ex`

This task only renames — no algorithm changes. All existing tests must pass with the new name.

- [ ] **Step 1: Rename the source file and update module name**

```bash
git mv lib/ancestry/people/person_tree.ex lib/ancestry/people/person_graph.ex
```

In `lib/ancestry/people/person_graph.ex`, change:

```elixir
# Old:
defmodule Ancestry.People.PersonTree do
# New:
defmodule Ancestry.People.PersonGraph do
```

- [ ] **Step 2: Rename the test file and update module name + alias**

```bash
git mv test/ancestry/people/person_tree_test.exs test/ancestry/people/person_graph_test.exs
```

In `test/ancestry/people/person_graph_test.exs`, change:

```elixir
# Old:
defmodule Ancestry.People.PersonTreeTest do
  ...
  alias Ancestry.People.PersonTree
  ...
  tree = PersonTree.build(...)

# New:
defmodule Ancestry.People.PersonGraphTest do
  ...
  alias Ancestry.People.PersonGraph
  ...
  tree = PersonGraph.build(...)
```

Replace all `PersonTree` references with `PersonGraph` in the test file (8 occurrences: module name on line 1, alias on line 6, and call sites on lines 33, 52, 91, 119, 137, 147).

- [ ] **Step 3: Update FamilyLive.Show alias and call sites**

In `lib/web/live/family_live/show.ex`:

Line 13 — update alias:
```elixir
# Old:
alias Ancestry.People.PersonTree
# New:
alias Ancestry.People.PersonGraph
```

Lines 98, 181, 613 — update call sites:
```elixir
# Old:
PersonTree.build(focus_person, socket.assigns.family_graph)
# New:
PersonGraph.build(focus_person, socket.assigns.family_graph)
```

There are exactly 3 call sites. Search for `PersonTree.build` to find them all.

- [ ] **Step 4: Run tests to verify rename is clean**

```bash
mix test test/ancestry/people/person_graph_test.exs
```

Expected: all 5 existing tests pass.

```bash
mix test
```

Expected: full suite green.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "Rename PersonTree to PersonGraph

Module, file, test, and all references updated. No behavior changes."
```

---

### Task 2: Add opts keyword list with depth controls

**Files:**
- Modify: `lib/ancestry/people/person_graph.ex`
- Modify: `test/ancestry/people/person_graph_test.exs`

Replace the hardcoded `@max_depth 3` with configurable opts. No visited-map changes yet — this task only parameterizes depth.

- [ ] **Step 1: Write failing tests for depth controls**

Add to `test/ancestry/people/person_graph_test.exs`:

```elixir
describe "depth controls" do
  setup do
    family = family_fixture()
    {:ok, child} = People.create_person(family, %{given_name: "Child", surname: "D"})
    {:ok, parent} = People.create_person(family, %{given_name: "Parent", surname: "D"})
    {:ok, grandparent} = People.create_person(family, %{given_name: "Grandparent", surname: "D"})
    {:ok, great_gp} = People.create_person(family, %{given_name: "GreatGP", surname: "D"})
    {:ok, kid} = People.create_person(family, %{given_name: "Kid", surname: "D"})
    {:ok, grandkid} = People.create_person(family, %{given_name: "Grandkid", surname: "D"})

    {:ok, _} = Relationships.create_relationship(grandparent, parent, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(great_gp, grandparent, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(parent, child, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(child, kid, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(kid, grandkid, "parent", %{role: "father"})

    graph = FamilyGraph.for_family(family.id)
    %{child: child, parent: parent, grandparent: grandparent, great_gp: great_gp, kid: kid, grandkid: grandkid, graph: graph, family: family}
  end

  test "ancestors: 0 shows no ancestors", %{child: child, graph: graph} do
    tree = PersonGraph.build(child, graph, ancestors: 0)
    assert tree.ancestors == nil
  end

  test "ancestors: 1 shows parents only", %{child: child, parent: parent, graph: graph} do
    tree = PersonGraph.build(child, graph, ancestors: 1)
    assert tree.ancestors != nil
    assert tree.ancestors.couple.person_a.id == parent.id
    assert tree.ancestors.parent_trees == []
  end

  test "ancestors: 2 shows parents and grandparents", %{child: child, graph: graph} do
    tree = PersonGraph.build(child, graph, ancestors: 2)
    assert tree.ancestors != nil
    assert length(tree.ancestors.parent_trees) == 1
  end

  test "ancestors: 3 shows three generations up", %{child: child, graph: graph} do
    tree = PersonGraph.build(child, graph, ancestors: 3)
    assert tree.ancestors != nil
    [gp_entry] = tree.ancestors.parent_trees
    assert length(gp_entry.tree.parent_trees) == 1
  end

  test "descendants: 0 shows no children", %{child: child, graph: graph} do
    tree = PersonGraph.build(child, graph, descendants: 0)
    assert tree.center.partner_children == []
    assert tree.center.solo_children == []
  end

  test "descendants: 2 shows grandchildren", %{child: child, graph: graph} do
    tree = PersonGraph.build(child, graph, descendants: 2)
    assert length(tree.center.solo_children) == 1
    [kid_unit] = tree.center.solo_children
    assert length(kid_unit.solo_children) == 1
  end

  test "default opts are ancestors: 2, descendants: 1", %{child: child, graph: graph} do
    tree = PersonGraph.build(child, graph)
    # ancestors: 2 — should have parents + grandparents
    assert tree.ancestors != nil
    assert length(tree.ancestors.parent_trees) == 1
    # descendants: 1 — should have children but not grandchildren
    assert length(tree.center.solo_children) == 1
    [kid_unit] = tree.center.solo_children
    # At depth limit — has_more should be true if grandkid exists
    assert kid_unit.has_more == true
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
mix test test/ancestry/people/person_graph_test.exs --trace
```

Expected: new tests fail because `build/3` doesn't accept opts yet.

- [ ] **Step 3: Implement opts in PersonGraph**

In `lib/ancestry/people/person_graph.ex`:

1. Remove `@max_depth 3`.

2. Update `build/2` to `build/3`:

```elixir
@default_opts [ancestors: 2, descendants: 1, other: 0]

# Elixir does not allow two clauses to each declare a default.
# Use an explicit build/2 head that delegates to build/3.
def build(focus_person, graph_or_id), do: build(focus_person, graph_or_id, [])

def build(%Person{} = focus_person, family_id, opts) when is_integer(family_id) do
  build(focus_person, FamilyGraph.for_family(family_id), opts)
end

def build(%Person{} = focus_person, %FamilyGraph{} = graph, opts) do
  opts = Keyword.merge(@default_opts, opts)

  center = build_family_unit_full(focus_person, 0, opts, graph)
  ancestor_tree = build_ancestor_tree(focus_person.id, 1, opts, graph)

  %__MODULE__{
    focus_person: focus_person,
    ancestors: ancestor_tree,
    center: center,
    family_id: graph.family_id
  }
end
```

Note: `build_ancestor_tree` now starts at generation `1` (parents), not `0`. The `generation` parameter now counts "how many generations up from focus" (1 = parents, 2 = grandparents). This matches the spec where `opts[:ancestors]` controls "how many generations upward to show."

3. Update `build_ancestor_tree` to use `opts[:ancestors]` instead of `@max_depth`:

```elixir
defp build_ancestor_tree(_person_id, generation, opts, _graph) when generation > opts[:ancestors] do
  nil
end

defp build_ancestor_tree(person_id, generation, opts, graph) do
  parents = FamilyGraph.parents(graph, person_id)
  # ... rest same as before, but pass opts to recursive calls:
  # build_ancestor_tree(person.id, generation + 1, opts, graph)
end
```

4. Update `build_family_unit_full` and `build_child_units` to use `opts[:descendants]`:

```elixir
defp build_family_unit_full(person, depth, opts, graph) do
  # ... same logic ...
  at_limit = depth + 1 >= opts[:descendants]
  # ... pass opts to build_child_units ...
end

defp build_child_units(_children, depth, _at_limit, _opts, _graph) when depth >= opts[:descendants] do
  []
end
```

Wait — the depth guard clause with `opts` won't work in a `when` guard because `opts` isn't a simple value. Instead, check inside the function body:

```elixir
defp build_child_units(children, depth, at_limit, opts, graph) do
  if depth >= opts[:descendants], do: [], else: do_build_child_units(children, depth, at_limit, opts, graph)
end
```

Or pass the max_descendants as a plain integer extracted from opts at the top of `build`:

```elixir
def build(%Person{} = focus_person, %FamilyGraph{} = graph, opts \\ []) do
  opts = Keyword.merge(@default_opts, opts)
  max_ancestors = opts[:ancestors]
  max_descendants = opts[:descendants]
  # pass these integers to private functions
end
```

This approach is cleaner — extract the integers once in `build` and thread them. Use this approach.

- [ ] **Step 4: Run tests**

```bash
mix test test/ancestry/people/person_graph_test.exs --trace
```

Expected: all tests pass, including existing ones (which now use default opts).

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/people/person_graph.ex test/ancestry/people/person_graph_test.exs
git commit -m "Add configurable depth controls to PersonGraph

Replace hardcoded @max_depth with opts keyword list:
ancestors (default 2), descendants (default 1), other (default 0)."
```

---

### Task 3: Add depth probe for parent ordering

**Files:**
- Modify: `lib/ancestry/people/person_graph.ex`
- Modify: `test/ancestry/people/person_graph_test.exs`

Add `max_ancestor_depth/3` and use it to sort the focus person's parents so the deeper lineage is traversed first.

- [ ] **Step 1: Write failing tests for parent ordering**

Add to `test/ancestry/people/person_graph_test.exs`:

```elixir
describe "deeper-parent-first ordering" do
  test "deeper parent becomes person_a in the ancestor couple" do
    family = family_fixture()
    {:ok, child} = People.create_person(family, %{given_name: "Child", surname: "D"})

    # Mom has deeper ancestry (3 generations)
    {:ok, mom} = People.create_person(family, %{given_name: "Mom", surname: "D", gender: "female"})
    {:ok, maternal_gm} = People.create_person(family, %{given_name: "MGM", surname: "D"})
    {:ok, maternal_ggm} = People.create_person(family, %{given_name: "MGGM", surname: "D"})
    {:ok, _} = Relationships.create_relationship(mom, child, "parent", %{role: "mother"})
    {:ok, _} = Relationships.create_relationship(maternal_gm, mom, "parent", %{role: "mother"})
    {:ok, _} = Relationships.create_relationship(maternal_ggm, maternal_gm, "parent", %{role: "mother"})

    # Dad has shallow ancestry (1 generation)
    {:ok, dad} = People.create_person(family, %{given_name: "Dad", surname: "D", gender: "male"})
    {:ok, _} = Relationships.create_relationship(dad, child, "parent", %{role: "father"})

    graph = FamilyGraph.for_family(family.id)
    tree = PersonGraph.build(child, graph, ancestors: 3)

    # Mom (deeper) should be person_a
    assert tree.ancestors.couple.person_a.id == mom.id
    assert tree.ancestors.couple.person_b.id == dad.id
  end

  test "single parent needs no sorting" do
    family = family_fixture()
    {:ok, child} = People.create_person(family, %{given_name: "Child", surname: "D"})
    {:ok, parent} = People.create_person(family, %{given_name: "Parent", surname: "D"})
    {:ok, _} = Relationships.create_relationship(parent, child, "parent", %{role: "father"})

    graph = FamilyGraph.for_family(family.id)
    tree = PersonGraph.build(child, graph)

    assert tree.ancestors.couple.person_a.id == parent.id
    assert tree.ancestors.couple.person_b == nil
  end

  test "depth probe terminates on cyclic data" do
    family = family_fixture()
    {:ok, person_a} = People.create_person(family, %{given_name: "A", surname: "D"})
    {:ok, person_b} = People.create_person(family, %{given_name: "B", surname: "D"})

    # Create a cycle: A is parent of B, B is parent of A (bad data)
    {:ok, _} = Relationships.create_relationship(person_a, person_b, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(person_b, person_a, "parent", %{role: "father"})

    graph = FamilyGraph.for_family(family.id)
    # Should not stack overflow
    tree = PersonGraph.build(person_a, graph)
    assert %PersonGraph{} = tree
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
mix test test/ancestry/people/person_graph_test.exs --trace
```

Expected: first test fails (parents not sorted by depth), third may hang/crash (no cycle protection in probe).

- [ ] **Step 3: Implement depth probe and parent sorting**

In `lib/ancestry/people/person_graph.ex`, add:

```elixir
defp max_ancestor_depth(person_id, graph, seen \\ MapSet.new()) do
  if MapSet.member?(seen, person_id) do
    0
  else
    seen = MapSet.put(seen, person_id)

    case FamilyGraph.parents(graph, person_id) do
      [] ->
        0

      parents ->
        parents
        |> Enum.map(fn {p, _rel} -> 1 + max_ancestor_depth(p.id, graph, seen) end)
        |> Enum.max()
    end
  end
end
```

In `build/3`, after extracting parents for the focus person's ancestor tree, sort them:

```elixir
def build(%Person{} = focus_person, %FamilyGraph{} = graph, opts \\ []) do
  opts = Keyword.merge(@default_opts, opts)

  ancestor_tree = build_ancestor_tree(focus_person.id, 1, opts, graph)
  center = build_family_unit_full(focus_person, 0, opts, graph)

  %__MODULE__{
    focus_person: focus_person,
    ancestors: ancestor_tree,
    center: center,
    family_id: graph.family_id
  }
end
```

In `build_ancestor_tree`, add sorting at generation 1:

```elixir
defp build_ancestor_tree(person_id, generation, opts, graph) do
  # ... after getting parents ...
  parents_sorted =
    if generation == 1 do
      # Sort by depth: deeper parent first
      Enum.sort_by(parents, fn {p, _rel} -> max_ancestor_depth(p.id, graph) end, :desc)
    else
      parents
    end

  {person_a, person_b} =
    case parents_sorted do
      [] -> {nil, nil}
      [{p, _}] -> {p, nil}
      [{p1, _}, {p2, _} | _] -> {p1, p2}
    end
  # ... rest unchanged ...
end
```

- [ ] **Step 4: Run tests**

```bash
mix test test/ancestry/people/person_graph_test.exs --trace
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/people/person_graph.ex test/ancestry/people/person_graph_test.exs
git commit -m "Add depth probe for deeper-parent-first ordering

Focus person's parents are sorted so the deeper lineage is
traversed first. Depth probe uses MapSet for cycle protection."
```

---

### Task 4: Thread visited map, cycle detection, and renderer update

**Files:**
- Modify: `lib/ancestry/people/person_graph.ex`
- Modify: `test/ancestry/people/person_graph_test.exs`
- Modify: `lib/web/live/family_live/person_card_component.ex`
- Modify: `lib/web/live/family_live/show.ex`

This is the core change. Thread a `%{person_id => generation}` visited map through all recursive calls. Mark duplicate persons with `duplicated: true`. Update the renderer and existing tests in the same task because the data shape change is not backward-compatible — ancestor person entries change from bare `%Person{}` to `%{person: %Person{}, duplicated: bool}`, which breaks the renderer and existing test assertions. These must all land together.

**Important:** `build_family_unit_full` must return `{result, visited}` from the start so that descendants are included in the visited map. This is required for the unified visited set.

- [ ] **Step 1: Write failing tests for cycle detection**

Create test data inline that reproduces cycle Types 1, 3, 4, and 5. Add to `test/ancestry/people/person_graph_test.exs`:

```elixir
describe "cycle detection" do
  test "Type 1: cousins who marry — shared grandparents marked duplicated" do
    family = family_fixture()
    p = fn attrs -> {:ok, p} = People.create_person(family, attrs); p end

    # Grandparents
    gpa = p.(%{given_name: "Grandpa", surname: "A", gender: "male"})
    gma = p.(%{given_name: "Grandma", surname: "A", gender: "female"})
    {:ok, _} = Relationships.create_relationship(gpa, gma, "married", %{marriage_year: 1940})

    # Two sons
    son_c = p.(%{given_name: "SonC", surname: "A", gender: "male"})
    son_d = p.(%{given_name: "SonD", surname: "A", gender: "male"})
    for son <- [son_c, son_d] do
      {:ok, _} = Relationships.create_relationship(gpa, son, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(gma, son, "parent", %{role: "mother"})
    end

    # Each son marries an unrelated wife
    wife_c = p.(%{given_name: "WifeC", surname: "C", gender: "female"})
    wife_d = p.(%{given_name: "WifeD", surname: "D", gender: "female"})
    {:ok, _} = Relationships.create_relationship(son_c, wife_c, "married", %{})
    {:ok, _} = Relationships.create_relationship(son_d, wife_d, "married", %{})

    # Cousins
    cousin_e = p.(%{given_name: "CousinE", surname: "A", gender: "male"})
    cousin_f = p.(%{given_name: "CousinF", surname: "A", gender: "female"})
    {:ok, _} = Relationships.create_relationship(son_c, cousin_e, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(wife_c, cousin_e, "parent", %{role: "mother"})
    {:ok, _} = Relationships.create_relationship(son_d, cousin_f, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(wife_d, cousin_f, "parent", %{role: "mother"})

    # Cousins marry
    {:ok, _} = Relationships.create_relationship(cousin_e, cousin_f, "married", %{})

    # Focus person (child of cousins)
    focus = p.(%{given_name: "Focus", surname: "A"})
    {:ok, _} = Relationships.create_relationship(cousin_e, focus, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(cousin_f, focus, "parent", %{role: "mother"})

    graph = FamilyGraph.for_family(family.id)
    tree = PersonGraph.build(focus, graph, ancestors: 3)

    # Both parents should exist in ancestors
    assert tree.ancestors != nil
    assert tree.ancestors.parent_trees != []

    # One path reaches grandparents normally, the other marks them duplicated
    all_couple_persons = collect_ancestor_persons(tree.ancestors)
    gpa_entries = Enum.filter(all_couple_persons, fn entry -> entry.person.id == gpa.id end)
    gma_entries = Enum.filter(all_couple_persons, fn entry -> entry.person.id == gma.id end)

    # Each grandparent appears twice: once not duplicated, once duplicated
    assert length(gpa_entries) == 2
    assert Enum.count(gpa_entries, & &1.duplicated) == 1
    assert Enum.count(gpa_entries, &(not &1.duplicated)) == 1

    assert length(gma_entries) == 2
    assert Enum.count(gma_entries, & &1.duplicated) == 1
    assert Enum.count(gma_entries, &(not &1.duplicated)) == 1
  end

  test "Type 4: uncle marries niece — grandparents stubbed on second path" do
    family = family_fixture()
    p = fn attrs -> {:ok, p} = People.create_person(family, attrs); p end

    # Grandparents
    gpa = p.(%{given_name: "Grandpa", surname: "K", gender: "male"})
    gma = p.(%{given_name: "Grandma", surname: "K", gender: "female"})
    {:ok, _} = Relationships.create_relationship(gpa, gma, "married", %{})

    # Two sons
    brother = p.(%{given_name: "Brother", surname: "K", gender: "male"})
    uncle = p.(%{given_name: "Uncle", surname: "K", gender: "male"})
    for son <- [brother, uncle] do
      {:ok, _} = Relationships.create_relationship(gpa, son, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(gma, son, "parent", %{role: "mother"})
    end

    # Brother marries wife, has a daughter (the niece)
    wife = p.(%{given_name: "Wife", surname: "W", gender: "female"})
    {:ok, _} = Relationships.create_relationship(brother, wife, "married", %{})
    niece = p.(%{given_name: "Niece", surname: "K", gender: "female"})
    {:ok, _} = Relationships.create_relationship(brother, niece, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(wife, niece, "parent", %{role: "mother"})

    # Uncle marries niece
    {:ok, _} = Relationships.create_relationship(uncle, niece, "married", %{})

    # Focus person (child of uncle + niece)
    focus = p.(%{given_name: "Focus", surname: "K"})
    {:ok, _} = Relationships.create_relationship(uncle, focus, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(niece, focus, "parent", %{role: "mother"})

    graph = FamilyGraph.for_family(family.id)
    tree = PersonGraph.build(focus, graph, ancestors: 3)

    # Grandparents should appear on the deeper side (Uncle's side) and be
    # duplicated on the other side (Niece -> Brother -> GPs)
    all_persons = collect_ancestor_persons(tree.ancestors)
    gpa_entries = Enum.filter(all_persons, fn e -> e.person.id == gpa.id end)

    # GPs appear twice: once full, once duplicated
    assert length(gpa_entries) == 2
    assert Enum.count(gpa_entries, & &1.duplicated) == 1
  end

  test "Type 5: siblings marry into same family — no duplication" do
    family = family_fixture()
    p = fn attrs -> {:ok, p} = People.create_person(family, attrs); p end

    # Family A
    gpa_a = p.(%{given_name: "GPA_A", surname: "A", gender: "male"})
    gma_a = p.(%{given_name: "GMA_A", surname: "A", gender: "female"})
    {:ok, _} = Relationships.create_relationship(gpa_a, gma_a, "married", %{})
    bro_x = p.(%{given_name: "BroX", surname: "A", gender: "male"})
    {:ok, _} = Relationships.create_relationship(gpa_a, bro_x, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(gma_a, bro_x, "parent", %{role: "mother"})

    # Family B
    gpa_b = p.(%{given_name: "GPA_B", surname: "B", gender: "male"})
    gma_b = p.(%{given_name: "GMA_B", surname: "B", gender: "female"})
    {:ok, _} = Relationships.create_relationship(gpa_b, gma_b, "married", %{})
    sis_x = p.(%{given_name: "SisX", surname: "B", gender: "female"})
    {:ok, _} = Relationships.create_relationship(gpa_b, sis_x, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(gma_b, sis_x, "parent", %{role: "mother"})

    # BroX marries SisX
    {:ok, _} = Relationships.create_relationship(bro_x, sis_x, "married", %{})
    focus = p.(%{given_name: "Focus", surname: "A"})
    {:ok, _} = Relationships.create_relationship(bro_x, focus, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(sis_x, focus, "parent", %{role: "mother"})

    graph = FamilyGraph.for_family(family.id)
    tree = PersonGraph.build(focus, graph, ancestors: 2)

    # No person should be duplicated — partner edges don't create cycles
    all_persons = collect_ancestor_persons(tree.ancestors)
    assert Enum.all?(all_persons, fn e -> not e.duplicated end)
  end

  test "no-cycle family has no duplicated persons" do
    family = family_fixture()
    {:ok, child} = People.create_person(family, %{given_name: "Child", surname: "D"})
    {:ok, dad} = People.create_person(family, %{given_name: "Dad", surname: "D"})
    {:ok, mom} = People.create_person(family, %{given_name: "Mom", surname: "D"})
    {:ok, _} = Relationships.create_relationship(dad, child, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(mom, child, "parent", %{role: "mother"})

    graph = FamilyGraph.for_family(family.id)
    tree = PersonGraph.build(child, graph)

    all_persons = collect_ancestor_persons(tree.ancestors)
    assert Enum.all?(all_persons, fn e -> not e.duplicated end)
  end

  test "person appearing as both parents (bad data) — second marked duplicated" do
    family = family_fixture()
    {:ok, parent} = People.create_person(family, %{given_name: "Parent", surname: "D"})
    {:ok, child} = People.create_person(family, %{given_name: "Child", surname: "D"})
    {:ok, _} = Relationships.create_relationship(parent, child, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(parent, child, "parent", %{role: "mother"})

    graph = FamilyGraph.for_family(family.id)
    tree = PersonGraph.build(child, graph)

    assert tree.ancestors != nil
    couple = tree.ancestors.couple
    # One should be duplicated
    entries = [couple.person_a, couple.person_b] |> Enum.reject(&is_nil/1)
    assert length(entries) == 2
    assert Enum.count(entries, & &1.duplicated) == 1
  end

  test "focus person in visited prevents self-ancestor loop" do
    family = family_fixture()
    {:ok, person} = People.create_person(family, %{given_name: "Self", surname: "D"})
    # Person is their own parent (bad data)
    {:ok, _} = Relationships.create_relationship(person, person, "parent", %{role: "father"})

    graph = FamilyGraph.for_family(family.id)
    tree = PersonGraph.build(person, graph)

    # Should not stack overflow. Ancestor couple should have the person marked duplicated.
    assert tree.ancestors != nil
    assert tree.ancestors.couple.person_a.duplicated == true
  end
end

# Helper: collect all person entries from ancestor tree (recursive)
defp collect_ancestor_persons(nil), do: []

defp collect_ancestor_persons(%{couple: couple, parent_trees: parent_trees}) do
  persons =
    [couple.person_a, couple.person_b]
    |> Enum.reject(&is_nil/1)

  child_persons =
    Enum.flat_map(parent_trees, fn entry ->
      collect_ancestor_persons(entry.tree)
    end)

  persons ++ child_persons
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
mix test test/ancestry/people/person_graph_test.exs --trace
```

Expected: new cycle tests fail because person entries are bare `%Person{}` structs (no `.duplicated` field, no `.person` field).

- [ ] **Step 3: Implement visited-map threading**

In `lib/ancestry/people/person_graph.ex`:

1. Update `build/3` to initialize visited and thread it through both passes:

```elixir
def build(%Person{} = focus_person, %FamilyGraph{} = graph, opts) do
  opts = Keyword.merge(@default_opts, opts)
  visited = %{focus_person.id => 0}

  {ancestor_tree, visited} = build_ancestor_tree(focus_person.id, 1, opts, graph, visited)
  {center, _visited} = build_family_unit_full(focus_person, 0, opts, graph, visited)

  %__MODULE__{
    focus_person: focus_person,
    ancestors: ancestor_tree,
    center: center,
    family_id: graph.family_id
  }
end
```

Note: `build_family_unit_full` returns `{result, visited}` so descendant person IDs are included in the visited map. This is essential for the unified visited set.

2. Update `build_ancestor_tree` to thread visited and wrap persons:

```elixir
defp build_ancestor_tree(person_id, generation, opts, graph, visited) do
  if generation > opts[:ancestors] do
    {nil, visited}
  else
    parents = FamilyGraph.parents(graph, person_id)

    parents =
      if generation == 1 do
        Enum.sort_by(parents, fn {p, _rel} -> max_ancestor_depth(p.id, graph) end, :desc)
      else
        parents
      end

    case parents do
      [] ->
        {nil, visited}

      _ ->
        {person_a_raw, person_b_raw} =
          case parents do
            [{p, _}] -> {p, nil}
            [{p1, _}, {p2, _} | _] -> {p1, p2}
          end

        # Check visited for each parent, wrap with duplicated flag
        {person_a_entry, visited} = check_and_mark(person_a_raw, generation, visited)

        {person_b_entry, visited} =
          if person_b_raw, do: check_and_mark(person_b_raw, generation, visited), else: {nil, visited}

        # Build parent_trees only for non-duplicated persons
        {parent_trees, visited} =
          [person_a_entry, person_b_entry]
          |> Enum.reject(&is_nil/1)
          |> Enum.reject(& &1.duplicated)
          |> Enum.reduce({[], visited}, fn entry, {trees, vis} ->
            case build_ancestor_tree(entry.person.id, generation + 1, opts, graph, vis) do
              {nil, vis} ->
                {trees, vis}

              {tree, vis} ->
                {trees ++ [%{tree: tree, for_person_id: entry.person.id}], vis}
            end
          end)

        node = %{
          couple: %{person_a: person_a_entry, person_b: person_b_entry},
          parent_trees: parent_trees
        }

        {node, visited}
    end
  end
end

defp check_and_mark(person, generation, visited) do
  if Map.has_key?(visited, person.id) do
    {%{person: person, duplicated: true}, visited}
  else
    {%{person: person, duplicated: false}, Map.put(visited, person.id, generation)}
  end
end
```

3. Update `build_family_unit_full` to return `{result, visited}`:

```elixir
defp build_family_unit_full(person, depth, opts, graph, visited) do
  # ... same partner sorting logic ...
  # Partners are NOT checked against visited in Phase 1
  # (they will be in Phase 2 when laterals populate visited with ex-partners)

  # Thread visited through each child group, accumulating it
  {partner_children, visited} = build_child_units_acc(partner_children_raw, depth, at_limit, opts, graph, visited)
  # ... same for previous_partner_groups, ex_partner_groups, solo_children ...

  result = %{
    focus: person,
    partner: partner,
    previous_partners: previous_partner_groups,
    ex_partners: ex_partner_groups,
    partner_children: partner_children,
    solo_children: solo_children
  }

  {result, visited}
end
```

4. Update `build_child_units` to return `{result, visited}` (rename to `build_child_units_acc`):

```elixir
defp build_child_units_acc(children, depth, at_limit, opts, graph, visited) do
  Enum.reduce(children, {[], visited}, fn child, {units, vis} ->
    if Map.has_key?(vis, child.id) do
      # Stub: duplicated child
      {units ++ [%{person: child, duplicated: true, has_more: false, children: nil}], vis}
    else
      vis = Map.put(vis, child.id, -(depth + 1))  # negative for descendants

      if at_limit do
        # ... existing at-limit logic, return {units ++ [unit], vis} ...
      else
        # Recurse — build_family_unit_full returns {unit, vis}
        {unit, vis} = build_family_unit_full(child, depth + 1, opts, graph, vis)
        # ... return {units ++ [unit_with_has_more], vis} ...
      end
    end
  end)
end
```

- [ ] **Step 4: Update existing tests for new person entry shape**

In the existing `build/2 with family_id` test, update assertions:

```elixir
# Old:
assert tree.ancestors.couple.person_a.id == f1_parent.id
assert tree.ancestors.couple.person_b == nil

# New:
assert tree.ancestors.couple.person_a.person.id == f1_parent.id
assert tree.ancestors.couple.person_b == nil
```

In the `build/2 accepts a pre-built FamilyGraph` test:

```elixir
# Old:
assert tree.ancestors.couple.person_a.id == parent.id

# New:
assert tree.ancestors.couple.person_a.person.id == parent.id
```

Also update any depth control tests from Task 2 that access `.couple.person_a.id` — they now need `.couple.person_a.person.id`.

- [ ] **Step 5: Update renderer for new person entry shape**

In `lib/web/live/family_live/person_card_component.ex`:

Add `duplicated` attr to `person_card`:

```elixir
attr :duplicated, :boolean, default: false
```

When `duplicated: true`, add dimmed styling (`opacity-50`) and a "(duplicated)" label in the desktop name section.

Update `ancestor_subtree` to unwrap person entries and pass duplicated flag:

```elixir
<.couple_card
  person_a={unwrap_person(@node.couple.person_a)}
  person_b={unwrap_person(@node.couple.person_b)}
  person_a_duplicated={duplicated?(@node.couple.person_a)}
  person_b_duplicated={duplicated?(@node.couple.person_b)}
  family_id={@family_id}
  organization={@organization}
  focused_person_id={@focused_person_id}
/>
```

Add helpers:

```elixir
defp unwrap_person(nil), do: nil
defp unwrap_person(%Person{} = p), do: p
defp unwrap_person(%{person: p}), do: p

defp duplicated?(nil), do: false
defp duplicated?(%{duplicated: d}), do: d
defp duplicated?(_), do: false
```

Add `person_a_duplicated` and `person_b_duplicated` attrs to `couple_card` (default: false). Pass them through to the `person_card` calls inside `couple_card`.

- [ ] **Step 6: Run full test suite**

```bash
mix test
```

Expected: all tests pass — both PersonGraph unit tests and the full suite including LiveView tests.

- [ ] **Step 7: Commit**

```bash
git add lib/ancestry/people/person_graph.ex test/ancestry/people/person_graph_test.exs lib/web/live/family_live/person_card_component.ex lib/web/live/family_live/show.ex
git commit -m "Add cycle detection via visited-map threading

Thread %{person_id => generation} through all recursive calls.
Persons already in the visited map are marked duplicated: true
and their ancestry is not traversed further. Renderer updated
to handle new person entry shape with duplicated flag."
```

---

### Task 5: Add generation renumbering

**Files:**
- Modify: `lib/ancestry/people/person_graph.ex`
- Modify: `test/ancestry/people/person_graph_test.exs`

After building the tree with focus-relative generations (focus=0, parents=1, children=-1), renumber to top-down (top ancestor=0).

- [ ] **Step 1: Write failing tests for renumbering**

The generation values are stored in the visited map but are not currently exposed in the output. For testability, add the visited map (renumbered) as a field on `%PersonGraph{}`.

Add to `test/ancestry/people/person_graph_test.exs`:

```elixir
describe "generation renumbering" do
  test "simple 2-gen tree: grandparents=0, parents=1, focus=2" do
    family = family_fixture()
    {:ok, child} = People.create_person(family, %{given_name: "Child", surname: "D"})
    {:ok, parent} = People.create_person(family, %{given_name: "Parent", surname: "D"})
    {:ok, gp} = People.create_person(family, %{given_name: "GP", surname: "D"})
    {:ok, _} = Relationships.create_relationship(parent, child, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(gp, parent, "parent", %{role: "father"})

    graph = FamilyGraph.for_family(family.id)
    tree = PersonGraph.build(child, graph, ancestors: 2)

    assert tree.generations[gp.id] == 0
    assert tree.generations[parent.id] == 1
    assert tree.generations[child.id] == 2
  end

  test "with descendants: focus at max_ancestors, children below" do
    family = family_fixture()
    {:ok, person} = People.create_person(family, %{given_name: "Person", surname: "D"})
    {:ok, parent} = People.create_person(family, %{given_name: "Parent", surname: "D"})
    {:ok, kid} = People.create_person(family, %{given_name: "Kid", surname: "D"})
    {:ok, _} = Relationships.create_relationship(parent, person, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(person, kid, "parent", %{role: "father"})

    graph = FamilyGraph.for_family(family.id)
    tree = PersonGraph.build(person, graph, ancestors: 1, descendants: 1)

    assert tree.generations[parent.id] == 0
    assert tree.generations[person.id] == 1
    assert tree.generations[kid.id] == 2
  end

  test "asymmetric branches: max depth drives renumbering" do
    family = family_fixture()
    {:ok, child} = People.create_person(family, %{given_name: "Child", surname: "D"})
    {:ok, dad} = People.create_person(family, %{given_name: "Dad", surname: "D"})
    {:ok, mom} = People.create_person(family, %{given_name: "Mom", surname: "D"})
    {:ok, paternal_gp} = People.create_person(family, %{given_name: "PGP", surname: "D"})

    {:ok, _} = Relationships.create_relationship(dad, child, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(mom, child, "parent", %{role: "mother"})
    {:ok, _} = Relationships.create_relationship(paternal_gp, dad, "parent", %{role: "father"})

    graph = FamilyGraph.for_family(family.id)
    tree = PersonGraph.build(child, graph, ancestors: 2)

    # Paternal GP at gen 0 (deepest), Dad and Mom at gen 1, Child at gen 2
    assert tree.generations[paternal_gp.id] == 0
    assert tree.generations[dad.id] == 1
    assert tree.generations[mom.id] == 1
    assert tree.generations[child.id] == 2
  end

  test "no ancestors: focus is generation 0" do
    family = family_fixture()
    {:ok, person} = People.create_person(family, %{given_name: "Person", surname: "D"})

    graph = FamilyGraph.for_family(family.id)
    tree = PersonGraph.build(person, graph, ancestors: 0)

    assert tree.generations[person.id] == 0
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
mix test test/ancestry/people/person_graph_test.exs --trace
```

Expected: fail — no `generations` field on `%PersonGraph{}`.

- [ ] **Step 3: Implement renumbering**

1. Add `:generations` field to the struct:

```elixir
defstruct [:focus_person, :ancestors, :center, :descendants, :family_id, :generations]
```

2. In `build/3`, after building the tree, renumber and attach:

```elixir
def build(%Person{} = focus_person, %FamilyGraph{} = graph, opts) do
  opts = Keyword.merge(@default_opts, opts)
  visited = %{focus_person.id => 0}

  {ancestor_tree, visited} = build_ancestor_tree(focus_person.id, 1, opts, graph, visited)
  {center, visited} = build_family_unit_full(focus_person, 0, opts, graph, visited)

  max_gen = visited |> Map.values() |> Enum.max()

  generations =
    Map.new(visited, fn {person_id, gen} -> {person_id, max_gen - gen} end)

  %__MODULE__{
    focus_person: focus_person,
    ancestors: ancestor_tree,
    center: center,
    family_id: graph.family_id,
    generations: generations
  }
end
```

Note: `build_family_unit_full` already returns `{center, visited}` from Task 4. The only new piece is computing `max_gen` and `generations` from the final visited map.

- [ ] **Step 4: Run tests**

```bash
mix test test/ancestry/people/person_graph_test.exs --trace
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/people/person_graph.ex test/ancestry/people/person_graph_test.exs
git commit -m "Add generation renumbering to PersonGraph

Visited map renumbered from focus-relative to top-down
(top ancestor = 0). Exposed as :generations field on the struct."
```

---

### Task 6: Add has_more indicators at ancestor depth boundary

**Files:**
- Modify: `lib/ancestry/people/person_graph.ex`
- Modify: `test/ancestry/people/person_graph_test.exs`

When the ancestor traversal stops at the depth limit, set `has_more: true` on the couple node if the person has parents beyond the boundary.

- [ ] **Step 1: Write failing test**

Add to `test/ancestry/people/person_graph_test.exs`:

```elixir
describe "has_more indicators" do
  test "ancestor at depth boundary shows has_more when more ancestors exist" do
    family = family_fixture()
    {:ok, child} = People.create_person(family, %{given_name: "Child", surname: "D"})
    {:ok, parent} = People.create_person(family, %{given_name: "Parent", surname: "D"})
    {:ok, gp} = People.create_person(family, %{given_name: "GP", surname: "D"})
    {:ok, ggp} = People.create_person(family, %{given_name: "GGP", surname: "D"})

    {:ok, _} = Relationships.create_relationship(parent, child, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(gp, parent, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(ggp, gp, "parent", %{role: "father"})

    graph = FamilyGraph.for_family(family.id)
    # ancestors: 1 means show parents only. GP exists but is beyond the limit.
    tree = PersonGraph.build(child, graph, ancestors: 1)

    assert tree.ancestors != nil
    # The parent couple should indicate more exists above
    assert tree.ancestors.has_more == true
  end

  test "ancestor at depth boundary shows has_more false when no more ancestors" do
    family = family_fixture()
    {:ok, child} = People.create_person(family, %{given_name: "Child", surname: "D"})
    {:ok, parent} = People.create_person(family, %{given_name: "Parent", surname: "D"})

    {:ok, _} = Relationships.create_relationship(parent, child, "parent", %{role: "father"})

    graph = FamilyGraph.for_family(family.id)
    tree = PersonGraph.build(child, graph, ancestors: 1)

    assert tree.ancestors != nil
    assert tree.ancestors.has_more == false
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
mix test test/ancestry/people/person_graph_test.exs --trace
```

Expected: fails — no `has_more` field on ancestor nodes.

- [ ] **Step 3: Implement has_more on ancestor nodes**

In `build_ancestor_tree`, add `has_more` to the node. At `generation == opts[:ancestors]`, the recursive calls for parents return nil, so `parent_trees` is empty. The `has_more` flag distinguishes "no parents exist" from "parents exist but depth limit reached":

```elixir
has_more =
  parent_trees == [] and
    [person_a_entry, person_b_entry]
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(& &1.duplicated)
    |> Enum.any?(fn entry -> FamilyGraph.parents(graph, entry.person.id) != [] end)

node = %{
  couple: %{person_a: person_a_entry, person_b: person_b_entry},
  parent_trees: parent_trees,
  has_more: has_more
}
```

- [ ] **Step 4: Run tests**

```bash
mix test test/ancestry/people/person_graph_test.exs --trace
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/people/person_graph.ex test/ancestry/people/person_graph_test.exs
git commit -m "Add has_more indicator on ancestor depth boundary

Ancestor couple nodes set has_more: true when ancestors exist
beyond the depth limit but were not traversed."
```

---

### Task 7: Add missing cycle type tests

**Files:**
- Modify: `test/ancestry/people/person_graph_test.exs`

Add tests for cycle Types 2 and 3, plus the three-parents edge case, which were in the design spec but not covered in Task 4.

- [ ] **Step 1: Add Type 2 test**

```elixir
test "Type 2: woman marries two brothers — no duplication in Phase 1" do
  family = family_fixture()
  p = fn attrs -> {:ok, p} = People.create_person(family, attrs); p end

  # Grandparents
  gpa = p.(%{given_name: "Grandpa", surname: "A", gender: "male"})
  gma = p.(%{given_name: "Grandma", surname: "A", gender: "female"})
  {:ok, _} = Relationships.create_relationship(gpa, gma, "married", %{})

  brother1 = p.(%{given_name: "Brother1", surname: "A", gender: "male"})
  brother2 = p.(%{given_name: "Brother2", surname: "A", gender: "male"})
  for son <- [brother1, brother2] do
    {:ok, _} = Relationships.create_relationship(gpa, son, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(gma, son, "parent", %{role: "mother"})
  end

  mom = p.(%{given_name: "Mom", surname: "M", gender: "female"})
  {:ok, _} = Relationships.create_relationship(brother1, mom, "divorced", %{marriage_year: 1966})
  half_sib = p.(%{given_name: "HalfSib", surname: "A"})
  {:ok, _} = Relationships.create_relationship(brother1, half_sib, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(mom, half_sib, "parent", %{role: "mother"})

  {:ok, _} = Relationships.create_relationship(brother2, mom, "married", %{marriage_year: 1976})
  focus = p.(%{given_name: "Focus", surname: "A"})
  {:ok, _} = Relationships.create_relationship(brother2, focus, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(mom, focus, "parent", %{role: "mother"})

  graph = FamilyGraph.for_family(family.id)
  tree = PersonGraph.build(focus, graph, ancestors: 2)

  # In Phase 1 (no laterals), Brother1 only appears as ex-partner in center row.
  # He is NOT an ancestor, so no duplication should occur.
  all_ancestor_persons = collect_ancestor_persons(tree.ancestors)
  assert Enum.all?(all_ancestor_persons, fn e -> not e.duplicated end)
end
```

- [ ] **Step 2: Add Type 3 test**

```elixir
test "Type 3: double first cousins — both GP sets duplicated on second path" do
  family = family_fixture()
  p = fn attrs -> {:ok, p} = People.create_person(family, attrs); p end

  # Grandparents A
  gpa_a = p.(%{given_name: "GPA_A", surname: "P", gender: "male"})
  gma_a = p.(%{given_name: "GMA_A", surname: "P", gender: "female"})
  {:ok, _} = Relationships.create_relationship(gpa_a, gma_a, "married", %{})

  # Grandparents B
  gpa_b = p.(%{given_name: "GPA_B", surname: "T", gender: "male"})
  gma_b = p.(%{given_name: "GMA_B", surname: "T", gender: "female"})
  {:ok, _} = Relationships.create_relationship(gpa_b, gma_b, "married", %{})

  # Two brothers from family A
  bro_x = p.(%{given_name: "BroX", surname: "P", gender: "male"})
  bro_y = p.(%{given_name: "BroY", surname: "P", gender: "male"})
  for son <- [bro_x, bro_y] do
    {:ok, _} = Relationships.create_relationship(gpa_a, son, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(gma_a, son, "parent", %{role: "mother"})
  end

  # Two sisters from family B
  sis_x = p.(%{given_name: "SisX", surname: "T", gender: "female"})
  sis_y = p.(%{given_name: "SisY", surname: "T", gender: "female"})
  for d <- [sis_x, sis_y] do
    {:ok, _} = Relationships.create_relationship(gpa_b, d, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(gma_b, d, "parent", %{role: "mother"})
  end

  # Cross marriages
  {:ok, _} = Relationships.create_relationship(bro_x, sis_x, "married", %{})
  {:ok, _} = Relationships.create_relationship(bro_y, sis_y, "married", %{})

  # Double first cousins
  parent_1 = p.(%{given_name: "Parent1", surname: "P", gender: "male"})
  {:ok, _} = Relationships.create_relationship(bro_x, parent_1, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(sis_x, parent_1, "parent", %{role: "mother"})

  parent_2 = p.(%{given_name: "Parent2", surname: "P", gender: "female"})
  {:ok, _} = Relationships.create_relationship(bro_y, parent_2, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(sis_y, parent_2, "parent", %{role: "mother"})

  {:ok, _} = Relationships.create_relationship(parent_1, parent_2, "married", %{})
  focus = p.(%{given_name: "Focus", surname: "P"})
  {:ok, _} = Relationships.create_relationship(parent_1, focus, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(parent_2, focus, "parent", %{role: "mother"})

  graph = FamilyGraph.for_family(family.id)
  tree = PersonGraph.build(focus, graph, ancestors: 3)

  all_persons = collect_ancestor_persons(tree.ancestors)

  # Both GP-A grandparents should appear twice (once full, once duplicated)
  gpa_a_entries = Enum.filter(all_persons, fn e -> e.person.id == gpa_a.id end)
  assert length(gpa_a_entries) == 2
  assert Enum.count(gpa_a_entries, & &1.duplicated) == 1

  # Both GP-B grandparents should appear twice
  gpa_b_entries = Enum.filter(all_persons, fn e -> e.person.id == gpa_b.id end)
  assert length(gpa_b_entries) == 2
  assert Enum.count(gpa_b_entries, & &1.duplicated) == 1
end
```

- [ ] **Step 3: Add three-parents edge case test**

```elixir
test "three parents (bad data) — only first two used" do
  family = family_fixture()
  {:ok, child} = People.create_person(family, %{given_name: "Child", surname: "D"})
  {:ok, parent_a} = People.create_person(family, %{given_name: "ParentA", surname: "D"})
  {:ok, parent_b} = People.create_person(family, %{given_name: "ParentB", surname: "D"})
  {:ok, parent_c} = People.create_person(family, %{given_name: "ParentC", surname: "D"})
  {:ok, _} = Relationships.create_relationship(parent_a, child, "parent", %{role: "father"})
  {:ok, _} = Relationships.create_relationship(parent_b, child, "parent", %{role: "mother"})
  {:ok, _} = Relationships.create_relationship(parent_c, child, "parent", %{role: "other"})

  graph = FamilyGraph.for_family(family.id)
  tree = PersonGraph.build(child, graph)

  # Only two parents in the couple
  assert tree.ancestors != nil
  couple = tree.ancestors.couple
  person_ids = [couple.person_a, couple.person_b]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(& &1.person.id)
  assert length(person_ids) == 2
end
```

- [ ] **Step 4: Run tests**

```bash
mix test test/ancestry/people/person_graph_test.exs --trace
```

Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add test/ancestry/people/person_graph_test.exs
git commit -m "Add Type 2, Type 3, and three-parents edge case tests"
```

---

### Task 8: Update CLAUDE.md to reflect always-stub decision

**Files:**
- Modify: `lib/ancestry/people/CLAUDE.md`

The design spec decided against visual sharing (Strategy 2 in CLAUDE.md). Update the requirements doc to match.

- [ ] **Step 1: Update the cycle resolution section**

In `lib/ancestry/people/CLAUDE.md`, update the "Two Rules" section and "Summary" table to reflect that second occurrences are always "(duplicated)" stubs, regardless of whether they're at the same or different generation level. Remove references to "sharing" as a separate strategy. Keep the cycle type catalog as-is (the examples are still valid) but update the resolution descriptions.

- [ ] **Step 2: Commit**

```bash
git add lib/ancestry/people/CLAUDE.md
git commit -m "Update CLAUDE.md: always-stub replaces sharing strategy

Reflects brainstorming decision: second occurrences are always
'(duplicated)' stubs, no visual sharing for same-gen convergence."
```

---

### Task 9: Final integration — precommit and manual verification

**Files:**
- No new files — verification only

- [ ] **Step 1: Run precommit**

```bash
mix precommit
```

Expected: compile (warnings-as-errors), remove unused deps, format, and all tests pass.

- [ ] **Step 2: Seed test cycle data and verify visually**

```bash
mix run priv/repo/seeds_test_cycles.exs
iex -S mix phx.server
```

Open the browser and navigate to the "Cycle Test Org" families:

1. **Intermarried Clans** → Focus on Zara: verify grandparents appear twice (once full, once "(duplicated)")
2. **Intermarried Clans** → Focus on Felix: verify grandparents (Kemp) show duplication
3. **Intermarried Clans** → Focus on Quentin: verify both Pemberton and Thornton grandparents show duplication
4. **Intermarried Clans** → Focus on Noreen: verify NO duplication (Type 5)
5. **Blended Saga** → Focus on Victor: verify no duplication despite multiple ex-partners
6. **Prolific Elders** → Focus on Montague: verify normal rendering with many siblings (no duplication)

- [ ] **Step 3: Verify non-cycle families still render correctly**

Navigate to any existing non-cycle family. Verify:
- Tree renders without errors
- Person cards show correctly
- Navigation (clicking persons) works
- Add Parent / Add Partner / Add Child placeholders work

- [ ] **Step 4: Commit (if any fixes were needed)**

```bash
mix precommit
git add -A && git commit -m "Fix integration issues from PersonGraph migration"
```

Only commit if fixes were needed. If everything passed, skip this step.
