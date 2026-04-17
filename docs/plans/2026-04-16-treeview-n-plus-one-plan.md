# TreeView + Kinship N+1 Fix — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce family TreeView page load from ~468 DB queries to 4, and Kinship calculate from ~100+ to 0 (after a 2-query graph load), by introducing an in-memory `FamilyGraph` that indexes a family's persons and relationships.

**Architecture:** New `Ancestry.People.FamilyGraph` struct built from 2 queries (`list_people_for_family` + `list_relationships_for_family`), exposing lookup functions (`parents`, `children`, `active_partners`, etc.) that mirror `Ancestry.Relationships` but use map lookups. `PersonTree.build` and `Kinship.calculate` swap DB calls for `FamilyGraph` lookups. `FamilyLive.Show` and `KinshipLive` cache the graph in a socket assign.

**Tech Stack:** Elixir, Ecto, Phoenix LiveView

**Spec:** `docs/plans/2026-04-16-treeview-n-plus-one.md`

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `lib/ancestry/people/family_graph.ex` | In-memory graph struct + constructor + lookup API |
| Create | `test/ancestry/people/family_graph_test.exs` | Unit tests: graph construction, lookup parity with SQL, edge cases |
| Modify | `lib/ancestry/people/person_tree.ex` | Accept `%FamilyGraph{}` as second arg; replace `Relationships.*` calls with `FamilyGraph.*` |
| Modify | `test/ancestry/people/person_tree_test.exs` | Update nil-arity test; add graph-arity test |
| Modify | `lib/web/live/family_live/show.ex` | Build + cache `:family_graph` assign; use `refresh_graph_and_tree/1` |
| Modify | `lib/ancestry/kinship.ex` | New `calculate/3` accepting `%FamilyGraph{}`; rewrite BFS + path to use graph |
| Modify | `test/ancestry/kinship_test.exs` | Migrate all tests to `calculate/3` with graph |
| Modify | `lib/web/live/kinship_live.ex` | Build `:family_graph` in mount; pass to `Kinship.calculate/3` |
| Modify | `lib/ancestry/relationships.ex:189-211` | Collapse `get_relationship_partners/3` two-query `as_a ++ as_b` into single OR query |

---

## Task 1: Create `FamilyGraph` struct + constructor

**Files:**
- Create: `lib/ancestry/people/family_graph.ex`
- Test: `test/ancestry/people/family_graph_test.exs`

- [ ] **Step 1: Write the struct + `for_family/1` constructor (no lookup functions yet)**

```elixir
# lib/ancestry/people/family_graph.ex
defmodule Ancestry.People.FamilyGraph do
  @moduledoc """
  In-memory index of a family's persons and relationships.
  Built from two queries, enables zero-DB tree/kinship traversal.
  """

  alias Ancestry.People
  alias Ancestry.People.Person
  alias Ancestry.Relationships
  alias Ancestry.Relationships.Relationship

  defstruct [
    :family_id,
    :people_by_id,
    :parents_by_child,
    :children_by_parent,
    :partners_by_person
  ]

  @doc """
  Builds the graph from DB — exactly 2 queries.
  """
  def for_family(family_id) do
    people = People.list_people_for_family(family_id)
    relationships = Relationships.list_relationships_for_family(family_id)
    from(people, relationships, family_id)
  end

  @doc """
  Builds the graph from pre-loaded lists (0 queries).
  """
  def from(people, relationships, family_id) do
    people_by_id = Map.new(people, &{&1.id, &1})

    {parents_by_child, children_by_parent, partners_by_person} =
      build_indexes(relationships, people_by_id)

    %__MODULE__{
      family_id: family_id,
      people_by_id: people_by_id,
      parents_by_child: parents_by_child,
      children_by_parent: children_by_parent,
      partners_by_person: partners_by_person
    }
  end

  defp build_indexes(relationships, people_by_id) do
    acc = {%{}, %{}, %{}}

    Enum.reduce(relationships, acc, fn rel, {pbc, cbp, pbp} ->
      person_a = Map.get(people_by_id, rel.person_a_id)
      person_b = Map.get(people_by_id, rel.person_b_id)

      if is_nil(person_a) or is_nil(person_b) do
        {pbc, cbp, pbp}
      else
        case rel.type do
          "parent" ->
            # person_a is parent, person_b is child
            pbc = Map.update(pbc, rel.person_b_id, [{person_a, rel}], &[{person_a, rel} | &1])
            cbp = Map.update(cbp, rel.person_a_id, [person_b], &[person_b | &1])
            {pbc, cbp, pbp}

          type when type in ~w(married relationship divorced separated) ->
            # Bidirectional: index under both endpoints
            pbp =
              pbp
              |> Map.update(rel.person_a_id, [{person_b, rel}], &[{person_b, rel} | &1])
              |> Map.update(rel.person_b_id, [{person_a, rel}], &[{person_a, rel} | &1])

            {pbc, cbp, pbp}

          _ ->
            {pbc, cbp, pbp}
        end
      end
    end)
    |> then(fn {pbc, cbp, pbp} ->
      # Sort children by birth_year ASC NULLS LAST, then id ASC
      cbp =
        Map.new(cbp, fn {parent_id, children} ->
          sorted =
            Enum.sort_by(children, fn p ->
              {is_nil(p.birth_year), p.birth_year || 0, p.id}
            end)

          {parent_id, sorted}
        end)

      {pbc, cbp, pbp}
    end)
  end
end
```

- [ ] **Step 2: Write test for `for_family/1` — graph construction + query count**

```elixir
# test/ancestry/people/family_graph_test.exs
defmodule Ancestry.People.FamilyGraphTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.People
  alias Ancestry.People.FamilyGraph
  alias Ancestry.Relationships

  defp family_with_tree(_context) do
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})
    {:ok, family} = Ancestry.Families.create_family(org, %{name: "Test Family"})

    {:ok, grandpa} = People.create_person(family, %{given_name: "Grandpa", surname: "S"})
    {:ok, grandma} = People.create_person(family, %{given_name: "Grandma", surname: "S"})
    {:ok, parent} = People.create_person(family, %{given_name: "Parent", surname: "S"})
    {:ok, partner} = People.create_person(family, %{given_name: "Partner", surname: "S"})
    {:ok, child} = People.create_person(family, %{given_name: "Child", surname: "S", birth_year: 2010})
    {:ok, solo_child} = People.create_person(family, %{given_name: "Solo", surname: "S", birth_year: 2015})
    {:ok, ex} = People.create_person(family, %{given_name: "Ex", surname: "S"})

    {:ok, _} = Relationships.create_relationship(grandpa, parent, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(grandma, parent, "parent", %{role: "mother"})
    {:ok, _} = Relationships.create_relationship(parent, partner, "married", %{marriage_year: 2005})
    {:ok, _} = Relationships.create_relationship(parent, child, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(partner, child, "parent", %{role: "mother"})
    {:ok, _} = Relationships.create_relationship(parent, solo_child, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(parent, ex, "divorced", %{})

    %{
      family: family,
      grandpa: grandpa,
      grandma: grandma,
      parent: parent,
      partner: partner,
      child: child,
      solo_child: solo_child,
      ex: ex
    }
  end

  describe "for_family/1" do
    setup :family_with_tree

    test "emits exactly 2 DB queries", %{family: family} do
      ref = :telemetry.attach("test-query-count", [:ancestry, :repo, :query], fn _, _, _, _ ->
        send(self(), :query_fired)
      end, nil)

      _graph = FamilyGraph.for_family(family.id)

      :telemetry.detach("test-query-count")

      # Drain all :query_fired messages
      count = count_messages(:query_fired)
      assert count == 2, "Expected 2 queries, got #{count}"
    end

    test "people_by_id contains all family members", %{family: family} do
      graph = FamilyGraph.for_family(family.id)
      assert map_size(graph.people_by_id) == 7
    end

    test "parents_by_child indexes parent relationships only", %{family: family, parent: parent, grandpa: grandpa, grandma: grandma} do
      graph = FamilyGraph.for_family(family.id)

      parent_entries = Map.get(graph.parents_by_child, parent.id, [])
      parent_ids = Enum.map(parent_entries, fn {p, _r} -> p.id end) |> MapSet.new()
      assert MapSet.equal?(parent_ids, MapSet.new([grandpa.id, grandma.id]))
    end

    test "children_by_parent sorted by birth_year nulls last", %{family: family, parent: parent, child: child, solo_child: solo_child} do
      graph = FamilyGraph.for_family(family.id)

      children = Map.get(graph.children_by_parent, parent.id, [])
      child_ids = Enum.map(children, & &1.id)
      # child (2010) before solo_child (2015)
      assert child_ids == [child.id, solo_child.id]
    end

    test "partners_by_person is bidirectional", %{family: family, parent: parent, partner: partner} do
      graph = FamilyGraph.for_family(family.id)

      from_parent = Map.get(graph.partners_by_person, parent.id, [])
      from_partner = Map.get(graph.partners_by_person, partner.id, [])

      assert Enum.any?(from_parent, fn {p, _} -> p.id == partner.id end)
      assert Enum.any?(from_partner, fn {p, _} -> p.id == parent.id end)
    end
  end

  defp count_messages(msg) do
    receive do
      ^msg -> 1 + count_messages(msg)
    after
      0 -> 0
    end
  end
end
```

- [ ] **Step 3: Run tests to verify they pass**

Run: `mix test test/ancestry/people/family_graph_test.exs -v`
Expected: all 5 tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/ancestry/people/family_graph.ex test/ancestry/people/family_graph_test.exs
git commit -m "feat: add FamilyGraph struct with in-memory indexes

Loads a family's persons + relationships in 2 queries, builds indexed
maps for parents, children, and partners. Foundation for eliminating
N+1 queries in PersonTree and Kinship."
```

---

## Task 2: Add `FamilyGraph` lookup functions + parity tests

**Files:**
- Modify: `lib/ancestry/people/family_graph.ex`
- Modify: `test/ancestry/people/family_graph_test.exs`

- [ ] **Step 1: Add all 8 lookup functions to `FamilyGraph`**

Add these functions to `lib/ancestry/people/family_graph.ex`:

```elixir
  alias Ancestry.Relationships.Relationship

  @doc "Returns [{%Person{}, %Relationship{}}] for active partners (married, relationship)."
  def active_partners(%__MODULE__{} = graph, person_id) do
    graph.partners_by_person
    |> Map.get(person_id, [])
    |> Enum.filter(fn {_p, rel} -> Relationship.active_partner_type?(rel.type) end)
  end

  @doc "Returns [{%Person{}, %Relationship{}}] for former partners (divorced, separated)."
  def former_partners(%__MODULE__{} = graph, person_id) do
    graph.partners_by_person
    |> Map.get(person_id, [])
    |> Enum.filter(fn {_p, rel} -> Relationship.former_partner_type?(rel.type) end)
  end

  @doc "Returns [{%Person{}, %Relationship{}}] — parents of the given child."
  def parents(%__MODULE__{} = graph, child_id) do
    Map.get(graph.parents_by_child, child_id, [])
  end

  @doc "Returns [%Person{}] — all children of the given parent."
  def children(%__MODULE__{} = graph, parent_id) do
    Map.get(graph.children_by_parent, parent_id, [])
  end

  @doc "Returns [%Person{}] — children of pair (both A and B are parents)."
  def children_of_pair(%__MODULE__{} = graph, parent_a_id, parent_b_id) do
    a_children = Map.get(graph.children_by_parent, parent_a_id, [])

    Enum.filter(a_children, fn child ->
      parent_ids =
        graph.parents_by_child
        |> Map.get(child.id, [])
        |> Enum.map(fn {p, _r} -> p.id end)
        |> MapSet.new()

      MapSet.member?(parent_ids, parent_b_id)
    end)
  end

  @doc "Returns [%Person{}] — children where this person is the ONLY parent."
  def solo_children(%__MODULE__{} = graph, person_id) do
    all_children = Map.get(graph.children_by_parent, person_id, [])

    Enum.filter(all_children, fn child ->
      parent_count = length(Map.get(graph.parents_by_child, child.id, []))
      parent_count == 1
    end)
  end

  @doc "Returns true if the person has any children."
  def has_children?(%__MODULE__{} = graph, person_id) do
    Map.get(graph.children_by_parent, person_id, []) != []
  end

  @doc "Fetches a person from the graph. Raises if not found."
  def fetch_person!(%__MODULE__{} = graph, person_id) do
    Map.fetch!(graph.people_by_id, person_id)
  end
```

- [ ] **Step 2: Write parity tests — graph lookups vs SQL**

Add this `describe` block to `test/ancestry/people/family_graph_test.exs`:

```elixir
  describe "lookup parity with Ancestry.Relationships" do
    setup :family_with_tree

    test "active_partners matches SQL", %{family: family, parent: parent} do
      graph = FamilyGraph.for_family(family.id)

      graph_result = FamilyGraph.active_partners(graph, parent.id)
      sql_result = Relationships.get_active_partners(parent.id, family_id: family.id)

      graph_ids = Enum.map(graph_result, fn {p, _} -> p.id end) |> MapSet.new()
      sql_ids = Enum.map(sql_result, fn {p, _} -> p.id end) |> MapSet.new()
      assert MapSet.equal?(graph_ids, sql_ids)
    end

    test "former_partners matches SQL", %{family: family, parent: parent} do
      graph = FamilyGraph.for_family(family.id)

      graph_result = FamilyGraph.former_partners(graph, parent.id)
      sql_result = Relationships.get_former_partners(parent.id, family_id: family.id)

      graph_ids = Enum.map(graph_result, fn {p, _} -> p.id end) |> MapSet.new()
      sql_ids = Enum.map(sql_result, fn {p, _} -> p.id end) |> MapSet.new()
      assert MapSet.equal?(graph_ids, sql_ids)
    end

    test "parents matches SQL", %{family: family, parent: parent} do
      graph = FamilyGraph.for_family(family.id)

      graph_result = FamilyGraph.parents(graph, parent.id)
      sql_result = Relationships.get_parents(parent.id, family_id: family.id)

      graph_ids = Enum.map(graph_result, fn {p, _} -> p.id end) |> MapSet.new()
      sql_ids = Enum.map(sql_result, fn {p, _} -> p.id end) |> MapSet.new()
      assert MapSet.equal?(graph_ids, sql_ids)
    end

    test "children matches SQL", %{family: family, parent: parent} do
      graph = FamilyGraph.for_family(family.id)

      graph_result = FamilyGraph.children(graph, parent.id)
      sql_result = Relationships.get_children(parent.id, family_id: family.id)

      assert Enum.map(graph_result, & &1.id) == Enum.map(sql_result, & &1.id)
    end

    test "children_of_pair matches SQL", %{family: family, parent: parent, partner: partner} do
      graph = FamilyGraph.for_family(family.id)

      graph_result = FamilyGraph.children_of_pair(graph, parent.id, partner.id)
      sql_result = Relationships.get_children_of_pair(parent.id, partner.id, family_id: family.id)

      assert Enum.map(graph_result, & &1.id) == Enum.map(sql_result, & &1.id)
    end

    test "solo_children matches SQL", %{family: family, parent: parent, child: child} do
      graph = FamilyGraph.for_family(family.id)

      graph_result = FamilyGraph.solo_children(graph, parent.id)
      sql_result = Relationships.get_solo_children(parent.id, family_id: family.id)

      assert Enum.map(graph_result, & &1.id) == Enum.map(sql_result, & &1.id)

      # Negative case: child with TWO parents must NOT appear in solo_children
      refute Enum.any?(graph_result, fn p -> p.id == child.id end)
    end

    test "has_children? returns true for a parent", %{family: family, parent: parent} do
      graph = FamilyGraph.for_family(family.id)
      assert FamilyGraph.has_children?(graph, parent.id)
    end

    test "has_children? returns false for a childless person", %{family: family, child: child} do
      graph = FamilyGraph.for_family(family.id)
      refute FamilyGraph.has_children?(graph, child.id)
    end

    test "fetch_person! returns the person", %{family: family, parent: parent} do
      graph = FamilyGraph.for_family(family.id)
      assert FamilyGraph.fetch_person!(graph, parent.id).id == parent.id
    end
  end

  describe "family scoping" do
    test "relationships crossing family boundary are excluded" do
      {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Scoping Org"})
      {:ok, family1} = Ancestry.Families.create_family(org, %{name: "Family 1"})
      {:ok, family2} = Ancestry.Families.create_family(org, %{name: "Family 2"})

      {:ok, person} = People.create_person(family1, %{given_name: "Shared", surname: "S"})
      People.add_to_family(person, family2)

      {:ok, outsider} = People.create_person(family2, %{given_name: "Outsider", surname: "S"})
      {:ok, _} = Relationships.create_relationship(outsider, person, "parent", %{role: "father"})

      graph = FamilyGraph.for_family(family1.id)

      # outsider is not in family1, so the parent relationship is excluded
      assert FamilyGraph.parents(graph, person.id) == []
    end
  end
```

- [ ] **Step 3: Run tests**

Run: `mix test test/ancestry/people/family_graph_test.exs -v`
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add lib/ancestry/people/family_graph.ex test/ancestry/people/family_graph_test.exs
git commit -m "feat: add FamilyGraph lookup API with SQL parity tests

8 lookup functions mirror the Ancestry.Relationships subset used by
PersonTree and Kinship. Parity tests compare graph results against
SQL for each function."
```

---

## Task 3: Wire `PersonTree.build` through `FamilyGraph`

**Files:**
- Modify: `lib/ancestry/people/person_tree.ex`
- Modify: `test/ancestry/people/person_tree_test.exs`

- [ ] **Step 1: Update `PersonTree.build/2` to accept `%FamilyGraph{}` or `family_id`**

Replace the entire content of `lib/ancestry/people/person_tree.ex` with the refactored version. Key changes:
- `build/2` pattern-matches on `%FamilyGraph{}` or integer `family_id`
- All private helpers take `graph` instead of `opts`
- Every `Relationships.X(id, opts)` → `FamilyGraph.X(graph, id)`
- Remove `build/1` default-nil path (add temporary nil handler for backwards compat)

```elixir
defmodule Ancestry.People.PersonTree do
  @moduledoc """
  Builds a person-centered family tree with N generations of ancestors
  above and N generations of descendants below a focus person.
  """

  alias Ancestry.People.FamilyGraph
  alias Ancestry.People.Person

  @max_depth 3

  defstruct [:focus_person, :ancestors, :center, :descendants, :family_id]

  @doc """
  Builds a person-centered tree. Accepts a family_id (builds graph internally)
  or a pre-built %FamilyGraph{} (zero queries).
  """
  def build(%Person{} = focus_person, family_id) when is_integer(family_id) do
    build(focus_person, FamilyGraph.for_family(family_id))
  end

  def build(%Person{} = focus_person, %FamilyGraph{} = graph) do
    center = build_family_unit_full(focus_person, 0, graph)
    ancestor_tree = build_ancestor_tree(focus_person.id, 0, graph)

    %__MODULE__{
      focus_person: focus_person,
      ancestors: ancestor_tree,
      center: center,
      family_id: graph.family_id
    }
  end

  # No nil-arity or build/1 — removed entirely. All callers must pass family_id or graph.

  # --- Center Row ---

  @doc """
  Builds a full family unit for a person, including partner, ex-partners,
  and children grouped by couple. Recurses for descendant generations.
  """
  defp build_family_unit_full(person, depth, %FamilyGraph{} = graph) do
    partners = FamilyGraph.active_partners(graph, person.id)
    ex_partners = FamilyGraph.former_partners(graph, person.id)

    # Sort partners: latest marriage year first, then highest person id as tiebreaker
    sorted_partners =
      Enum.sort_by(
        partners,
        fn {p, rel} ->
          year = if rel.metadata, do: Map.get(rel.metadata, :marriage_year), else: nil
          {year || 0, p.id}
        end,
        :desc
      )

    # Latest partner is the main couple partner; rest are previous partners
    {partner, previous} =
      case sorted_partners do
        [{p, _rel} | rest] -> {p, rest}
        [] -> {nil, []}
      end

    at_limit = depth + 1 >= @max_depth

    # Children with current partner
    partner_children =
      if partner do
        FamilyGraph.children_of_pair(graph, person.id, partner.id)
        |> build_child_units(depth, at_limit, graph)
      else
        []
      end

    # Children with each previous (non-ex) partner
    previous_partner_groups =
      Enum.map(previous, fn {prev, _rel} ->
        children =
          FamilyGraph.children_of_pair(graph, person.id, prev.id)
          |> build_child_units(depth, at_limit, graph)

        %{person: prev, children: children}
      end)

    # Children with each ex-partner
    ex_partner_groups =
      Enum.map(ex_partners, fn {ex, _rel} ->
        children =
          FamilyGraph.children_of_pair(graph, person.id, ex.id)
          |> build_child_units(depth, at_limit, graph)

        %{person: ex, children: children}
      end)

    # Solo children (no co-parent)
    solo_children =
      FamilyGraph.solo_children(graph, person.id)
      |> build_child_units(depth, at_limit, graph)

    %{
      focus: person,
      partner: partner,
      previous_partners: previous_partner_groups,
      ex_partners: ex_partner_groups,
      partner_children: partner_children,
      solo_children: solo_children
    }
  end

  defp build_child_units(_children, depth, _at_limit, _graph) when depth >= @max_depth, do: []

  defp build_child_units(children, depth, at_limit, graph) do
    Enum.map(children, fn child ->
      if at_limit do
        # At the limit — just check if they have more, don't recurse
        has_more = FamilyGraph.has_children?(graph, child.id)
        partners = FamilyGraph.active_partners(graph, child.id)

        partner =
          case partners do
            [{p, _} | _] -> p
            [] -> nil
          end

        %{person: child, partner: partner, has_more: has_more, children: nil}
      else
        # Recurse to build the full subtree
        unit = build_family_unit_full(child, depth + 1, graph)

        has_children =
          unit.partner_children != [] or unit.solo_children != [] or unit.ex_partners != []

        Map.put(unit, :has_more, false) |> Map.put(:has_children, has_children)
      end
    end)
  end

  # --- Ancestors (recursive tree) ---

  defp build_ancestor_tree(_person_id, depth, _graph) when depth >= @max_depth, do: nil

  defp build_ancestor_tree(person_id, depth, graph) do
    parents = FamilyGraph.parents(graph, person_id)

    {person_a, person_b} =
      case parents do
        [] -> {nil, nil}
        [{p, _}] -> {p, nil}
        [{p1, _}, {p2, _} | _] -> {p1, p2}
      end

    if is_nil(person_a) and is_nil(person_b) do
      nil
    else
      parent_trees =
        [person_a, person_b]
        |> Enum.reject(&is_nil/1)
        |> Enum.map(fn person ->
          case build_ancestor_tree(person.id, depth + 1, graph) do
            nil -> nil
            tree -> %{tree: tree, for_person_id: person.id}
          end
        end)
        |> Enum.reject(&is_nil/1)

      %{
        couple: %{person_a: person_a, person_b: person_b},
        parent_trees: parent_trees
      }
    end
  end
end
```

- [ ] **Step 2: Update `person_tree_test.exs` — remove nil-arity test + add graph-arity test**

In `test/ancestry/people/person_tree_test.exs`:

1. Add alias: `alias Ancestry.People.FamilyGraph`

2. **Delete** the entire test at line 44-53 (`"build/1 without family_id returns all relatives (backwards compat)"`). The nil arity is removed — no longer needs coverage.

3. **Add** a new test in the same describe block:

```elixir
    test "build/2 accepts a pre-built FamilyGraph" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "Person", surname: "P"})
      {:ok, parent} = People.create_person(family, %{given_name: "Parent", surname: "P"})
      {:ok, _} = Relationships.create_relationship(parent, person, "parent", %{role: "father"})

      graph = FamilyGraph.for_family(family.id)
      tree = PersonTree.build(person, graph)
      assert tree.ancestors != nil
      assert tree.ancestors.couple.person_a.id == parent.id
    end
```

- [ ] **Step 3: Run all PersonTree tests + FamilyGraph tests**

Run: `mix test test/ancestry/people/ -v`
Expected: all tests pass. The existing family-scoped tests exercise the new FamilyGraph path.

- [ ] **Step 4: Run the full test suite**

Run: `mix test`
Expected: all green. No other module depends on PersonTree internals.

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/people/person_tree.ex test/ancestry/people/person_tree_test.exs
git commit -m "refactor: wire PersonTree.build through FamilyGraph

PersonTree now accepts %FamilyGraph{} as second arg. All internal
helpers use graph lookups instead of per-node DB queries. Legacy
family_id integer arity builds the graph internally. Existing tests
remain green — they now exercise the new path."
```

---

## Task 4: Update `FamilyLive.Show` to cache graph + use `refresh_graph_and_tree/1`

**Files:**
- Modify: `lib/web/live/family_live/show.ex`

- [ ] **Step 1: Read the current `show.ex` to understand all call sites**

Read `lib/web/live/family_live/show.ex` — specifically mount/3, handle_params/3, and the 5 `PersonTree.build` call sites at lines 93, 174, 356, 420, 580. Also read the `handle_event("save", ...)` handler around line 157 to understand the default-person change path.

- [ ] **Step 2: Add `:family_graph` assign and `refresh_graph_and_tree/1` helper**

In `lib/web/live/family_live/show.ex`:

1. Add alias at top: `alias Ancestry.People.FamilyGraph`
2. In `mount/3`, after `people = People.list_people_for_family(family_id)` add:
   ```elixir
   relationships = Ancestry.Relationships.list_relationships_for_family(family_id)
   family_graph = FamilyGraph.from(people, relationships, family.id)
   ```
   And add `|> assign(:family_graph, family_graph)` to the socket pipeline.

3. Add private helper at bottom of module:
   ```elixir
   defp refresh_graph_and_tree(socket) do
     family_id = socket.assigns.family.id
     people = People.list_people_for_family(family_id)
     relationships = Ancestry.Relationships.list_relationships_for_family(family_id)
     graph = FamilyGraph.from(people, relationships, family_id)

     tree =
       case socket.assigns.focus_person do
         nil -> nil
         focus -> PersonTree.build(focus, graph)
       end

     assign(socket, people: people, family_graph: graph, tree: tree)
   end
   ```

- [ ] **Step 3: Update `handle_params` (line 93) — use cached graph**

Change:
```elixir
    tree =
      if focus_person do
        PersonTree.build(focus_person, socket.assigns.family.id)
      else
        nil
      end
```

To:
```elixir
    tree =
      if focus_person do
        PersonTree.build(focus_person, socket.assigns.family_graph)
      else
        nil
      end
```

- [ ] **Step 4: Update `handle_event("save", ...)` (line 174) — reuse cached graph**

The save handler may change the default person (and thus focus_person). Replace the tree rebuild at line 174 to use the cached graph:

Change `PersonTree.build(person, family.id)` to `PersonTree.build(person, socket.assigns.family_graph)`

- [ ] **Step 5: Update mutation handlers (lines 356, 420, 580) — use `refresh_graph_and_tree/1`**

For each of the three mutation handlers:

**Line 356** (`handle_event("link_person", ...)`): After linking the person, replace the manual tree rebuild with:
```elixir
socket = refresh_graph_and_tree(socket)
```

**Line 420** (inside `handle_event("close_import", ...)` — this is the handler that reloads people + rebuilds the tree after import, NOT `import_csv` itself): Replace the manual people reload + tree rebuild with `refresh_graph_and_tree(socket)`.

**Line 580** (`handle_info({:relationship_saved, ...})`): Replace the manual people reload + tree rebuild with `refresh_graph_and_tree(socket)`.

- [ ] **Step 6: Run the full test suite**

Run: `mix test`
Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add lib/web/live/family_live/show.ex
git commit -m "perf: cache FamilyGraph in FamilyLive.Show

Graph built once in mount (1 extra query for relationships). Read-only
paths (handle_params, refocus) use the cached graph — 0 DB queries.
Mutation paths call refresh_graph_and_tree/1 — 2 queries regardless
of tree size."
```

---

## Task 5: Migrate `Kinship` + `KinshipLive` to `FamilyGraph`

**Files:**
- Modify: `lib/ancestry/kinship.ex`
- Modify: `test/ancestry/kinship_test.exs`
- Modify: `lib/web/live/kinship_live.ex`

- [ ] **Step 1: Add `Kinship.calculate/3` that takes a `%FamilyGraph{}`**

In `lib/ancestry/kinship.ex`:

1. Add alias: `alias Ancestry.People.FamilyGraph`

2. Replace `calculate/2` with `calculate/3`:

```elixir
  def calculate(person_a_id, person_b_id, _graph) when person_a_id == person_b_id do
    {:error, :same_person}
  end

  def calculate(person_a_id, person_b_id, %FamilyGraph{} = graph) do
    ancestors_a = build_ancestor_map(person_a_id, graph)
    ancestors_b = build_ancestor_map(person_b_id, graph)

    common_ancestor_ids =
      ancestors_a
      |> Map.keys()
      |> MapSet.new()
      |> MapSet.intersection(MapSet.new(Map.keys(ancestors_b)))

    if MapSet.size(common_ancestor_ids) == 0 do
      {:error, :no_common_ancestor}
    else
      {mrca_id, steps_a, steps_b, path_a, path_b} =
        common_ancestor_ids
        |> Enum.map(fn id ->
          {depth_a, pa} = Map.fetch!(ancestors_a, id)
          {depth_b, pb} = Map.fetch!(ancestors_b, id)
          {id, depth_a, depth_b, pa, pb}
        end)
        |> Enum.min_by(fn {_id, da, db, _pa, _pb} -> da + db end)

      mrca = FamilyGraph.fetch_person!(graph, mrca_id)
      half? = half_relationship?(mrca_id, steps_a, steps_b, ancestors_a, ancestors_b)
      relationship = classify(steps_a, steps_b, half?)
      path = build_path(path_a, path_b, steps_a, steps_b, graph)
      dna_pct = dna_percentage(steps_a, steps_b, half?)

      {:ok,
       %__MODULE__{
         relationship: relationship,
         steps_a: steps_a,
         steps_b: steps_b,
         path: path,
         mrca: mrca,
         half?: half?,
         dna_percentage: dna_pct
       }}
    end
  end
```

3. Update `build_ancestor_map/2` → `build_ancestor_map/2` taking graph:

```elixir
  defp build_ancestor_map(person_id, graph) do
    initial = %{person_id => {0, [person_id]}}
    bfs_expand([person_id], initial, 1, graph)
  end

  defp bfs_expand(_frontier, ancestors, depth, _graph) when depth > @max_depth, do: ancestors
  defp bfs_expand([], ancestors, _depth, _graph), do: ancestors

  defp bfs_expand(frontier, ancestors, depth, graph) do
    next_frontier =
      frontier
      |> Enum.flat_map(fn person_id ->
        FamilyGraph.parents(graph, person_id)
        |> Enum.map(fn {parent, _rel} -> {parent.id, person_id} end)
      end)
      |> Enum.reject(fn {parent_id, _child_id} -> Map.has_key?(ancestors, parent_id) end)

    new_ancestors =
      Enum.reduce(next_frontier, ancestors, fn {parent_id, child_id}, acc ->
        {_child_depth, child_path} = Map.fetch!(acc, child_id)
        Map.put(acc, parent_id, {depth, child_path ++ [parent_id]})
      end)

    new_frontier_ids =
      next_frontier
      |> Enum.map(fn {parent_id, _} -> parent_id end)
      |> Enum.uniq()

    bfs_expand(new_frontier_ids, new_ancestors, depth + 1, graph)
  end
```

4. Update `build_path/5` to use graph:

```elixir
  defp build_path(path_a, path_b, steps_a, steps_b, graph) do
    path_b_descending =
      path_b
      |> Enum.reverse()
      |> tl()

    full_ids = path_a ++ path_b_descending

    full_ids
    |> Enum.with_index()
    |> Enum.map(fn {id, index} ->
      person = FamilyGraph.fetch_person!(graph, id)
      label = path_label(index, steps_a, steps_b)
      %{person: person, label: label}
    end)
  end
```

5. Remove the old `calculate/2` (no-graph arity) entirely.

- [ ] **Step 2: Update all tests in `kinship_test.exs` to use `calculate/3`**

In `test/ancestry/kinship_test.exs`:

1. Add alias: `alias Ancestry.People.FamilyGraph`

2. In every setup block that creates a family, also build a graph:
   ```elixir
   graph = FamilyGraph.for_family(family.id)
   %{family: family, graph: graph, ...}
   ```

3. Replace every `Kinship.calculate(a.id, b.id)` with `Kinship.calculate(a.id, b.id, graph)`.

4. Add a test for the new family-scoped behavior:
   ```elixir
   test "returns :no_common_ancestor when ancestor is outside family" do
     family = family_fixture()
     # Use same org, different family — ancestor is not a member of `family`
     org = Ancestry.Organizations.get_organization!(family.organization_id)
     {:ok, other_family} = Ancestry.Families.create_family(org, %{name: "Other"})

     person_a = person_fixture(family, %{given_name: "A", surname: "S"})
     person_b = person_fixture(family, %{given_name: "B", surname: "S"})
     # Shared ancestor only in other_family, not in this family
     ancestor = person_fixture(other_family, %{given_name: "Ancestor", surname: "S"})

     make_parent!(ancestor, person_a, "father")
     make_parent!(ancestor, person_b, "father")

     graph = FamilyGraph.for_family(family.id)
     assert {:error, :no_common_ancestor} = Kinship.calculate(person_a.id, person_b.id, graph)
   end
   ```

- [ ] **Step 3: Update `KinshipLive` to build graph in mount and pass to calculate**

In `lib/web/live/kinship_live.ex`:

1. Add aliases:
   ```elixir
   alias Ancestry.People.FamilyGraph
   alias Ancestry.Relationships
   ```

2. In `mount/3`, after `people = People.list_people_for_family(family_id)`, add:
   ```elixir
   relationships = Relationships.list_relationships_for_family(family_id)
   family_graph = FamilyGraph.from(people, relationships, family.id)
   ```
   And add `|> assign(:family_graph, family_graph)` to the socket pipeline.

3. In `maybe_calculate/1`, change:
   ```elixir
   result = Kinship.calculate(a_id, b_id)
   ```
   To:
   ```elixir
   result = Kinship.calculate(a_id, b_id, socket.assigns.family_graph)
   ```

- [ ] **Step 4: Run kinship tests + E2E**

Run: `mix test test/ancestry/kinship_test.exs test/user_flows/calculating_kinship_test.exs -v`
Expected: all pass.

- [ ] **Step 5: Run full test suite**

Run: `mix test`
Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add lib/ancestry/kinship.ex test/ancestry/kinship_test.exs lib/web/live/kinship_live.ex
git commit -m "perf: migrate Kinship to FamilyGraph — 0 DB queries after mount

Kinship.calculate/3 takes a %FamilyGraph{}. BFS and path-building
use graph lookups instead of per-node queries. KinshipLive builds
graph in mount (2 queries), every subsequent calculation is pure
in-memory."
```

---

## Task 6: Collapse `get_relationship_partners` two-query split

**Files:**
- Modify: `lib/ancestry/relationships.ex:189-211`

- [ ] **Step 1: Rewrite `get_relationship_partners/3` to use one query with OR**

In `lib/ancestry/relationships.ex`, replace the `get_relationship_partners/3` function (lines 189-211):

```elixir
  defp get_relationship_partners(person_id, types, opts) do
    family_id = opts[:family_id]

    query =
      from(r in Relationship,
        join: p in Person,
        on:
          (r.person_a_id == ^person_id and p.id == r.person_b_id) or
            (r.person_b_id == ^person_id and p.id == r.person_a_id),
        where: r.type in ^types,
        select: {p, r}
      )

    query = maybe_filter_by_family(query, family_id)
    Repo.all(query)
  end
```

- [ ] **Step 2: Run tests**

Run: `mix test test/ancestry/relationships_test.exs test/ancestry/people/ test/ancestry/kinship_test.exs -v`
Expected: all pass. The two-query → one-query change is transparent to callers.

- [ ] **Step 3: Commit**

```bash
git add lib/ancestry/relationships.ex
git commit -m "refactor: collapse get_relationship_partners to single query

Replaces two-query as_a/as_b union with one query using OR. Halves
the DB round-trips for any caller still using this path (Kinship's
old arity was removed, but other callers like direct Relationships
API users benefit)."
```

---

## Task 7: Final verification + `mix precommit`

- [ ] **Step 1: Run `mix precommit`**

Run: `mix precommit`
Expected: compile (warnings-as-errors), unused deps check, format, and all tests pass.

- [ ] **Step 2: Manual verification with the dev server**

Start `iex -S mix phx.server` and navigate to `http://localhost:4000/org/1/families/9?person=348`.

Check the server logs. Count `[debug] QUERY OK` lines between the `GET /org/1/families/9` and `Replied in` — should be ≤ ~12 total queries (auth, org, family, persons, relationships, galleries, vaults, metrics, default person). The `PersonTree` and `FamilyGraph` paths should emit **0 additional queries** beyond the initial 2 for graph construction.

Click on a different person in the tree (refocus). Verify 0 new DB queries appear in the log.

Navigate to `/org/1/families/9/kinship?person_a=X&person_b=Y`. Verify kinship result displays and the log shows only mount queries, not per-BFS-node queries.

- [ ] **Step 3: Verify with Tidewave `get_logs`**

Use `mcp__tidewave__get_logs` to capture and inspect recent request logs for the same URLs, confirming query counts.
