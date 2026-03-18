# Family Tree Canvas View Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a visual family tree canvas to the FamilyLive.Show page that renders people and their relationships as a graph using HTML/CSS grid, with a side panel for galleries and people management.

**Architecture:** The `FamilyGraph` module builds an Erlang `:digraph` from people + relationships, computes a 2D grid layout, and outputs a struct of cells (person cards, union connectors, line connectors). LiveComponents render each section purely from assigns. The existing FamilyLive.Show page is restructured into a two-panel layout (canvas + side panel).

**Tech Stack:** Erlang `:digraph`/`:digraph_utils`, Phoenix LiveView, LiveComponents, CSS Grid, Tailwind CSS

---

### Task 1: Add `list_relationships_for_family/1` query

**Files:**
- Modify: `lib/ancestry/relationships.ex`
- Test: `test/ancestry/relationships_test.exs`

**Step 1: Write the failing test**

Add to `test/ancestry/relationships_test.exs`:

```elixir
describe "list_relationships_for_family/1" do
  test "returns relationships where both people are in the family" do
    family = family_fixture()
    {:ok, alice} = People.create_person(family, %{given_name: "Alice", surname: "A"})
    {:ok, bob} = People.create_person(family, %{given_name: "Bob", surname: "B"})
    {:ok, rel} = Relationships.create_relationship(alice, bob, "partner")

    results = Relationships.list_relationships_for_family(family.id)
    assert length(results) == 1
    assert hd(results).id == rel.id
  end

  test "excludes relationships where one person is outside the family" do
    family1 = family_fixture(%{name: "Family 1"})
    family2 = family_fixture(%{name: "Family 2"})
    {:ok, alice} = People.create_person(family1, %{given_name: "Alice", surname: "A"})
    {:ok, bob} = People.create_person(family2, %{given_name: "Bob", surname: "B"})
    {:ok, _rel} = Relationships.create_relationship(alice, bob, "partner")

    assert Relationships.list_relationships_for_family(family1.id) == []
  end

  test "returns all relationship types" do
    family = family_fixture()
    {:ok, parent} = People.create_person(family, %{given_name: "Parent", surname: "P"})
    {:ok, child} = People.create_person(family, %{given_name: "Child", surname: "C"})
    {:ok, partner} = People.create_person(family, %{given_name: "Partner", surname: "X"})
    {:ok, _} = Relationships.create_relationship(parent, child, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(parent, partner, "partner")

    results = Relationships.list_relationships_for_family(family.id)
    assert length(results) == 2
    types = Enum.map(results, & &1.type) |> Enum.sort()
    assert types == ["parent", "partner"]
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ancestry/relationships_test.exs --seed 0 2>&1 | tail -20`
Expected: Compilation error — `list_relationships_for_family/1` is undefined.

**Step 3: Write minimal implementation**

Add to `lib/ancestry/relationships.ex` (after `list_relationships_for_person/1` around line 71):

```elixir
@doc """
Returns all relationships where both person_a and person_b are members of the given family.
"""
def list_relationships_for_family(family_id) do
  alias Ancestry.People.FamilyMember

  from(r in Relationship,
    join: fm_a in FamilyMember,
    on: fm_a.person_id == r.person_a_id and fm_a.family_id == ^family_id,
    join: fm_b in FamilyMember,
    on: fm_b.person_id == r.person_b_id and fm_b.family_id == ^family_id
  )
  |> Repo.all()
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/ancestry/relationships_test.exs --seed 0 2>&1 | tail -10`
Expected: All tests pass.

**Step 5: Commit**

```
git add lib/ancestry/relationships.ex test/ancestry/relationships_test.exs
git commit -m "Add list_relationships_for_family/1 query"
```

---

### Task 2: Build FamilyGraph data structure and `:digraph` builder

This is the core algorithm. It takes people and relationships, builds an Erlang `:digraph`, identifies connected components, assigns generations, and outputs a flat node list. **No grid layout yet** — that comes in Task 3.

**Files:**
- Create: `lib/ancestry/people/family_graph.ex`
- Test: `test/ancestry/people/family_graph_test.exs`

**Step 1: Write the failing tests**

Create `test/ancestry/people/family_graph_test.exs`:

```elixir
defmodule Ancestry.People.FamilyGraphTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.People
  alias Ancestry.People.FamilyGraph
  alias Ancestry.Relationships

  defp family_fixture(attrs \\ %{}) do
    {:ok, family} =
      attrs
      |> Enum.into(%{name: "Test Family"})
      |> Ancestry.Families.create_family()

    family
  end

  describe "build/2 with empty data" do
    test "returns empty graph for no people" do
      graph = FamilyGraph.build([], [])
      assert graph.nodes == %{}
      assert graph.unions == []
      assert graph.components == []
      assert graph.unconnected == []
    end
  end

  describe "build/2 with unconnected people" do
    test "people with no relationships are unconnected" do
      family = family_fixture()
      {:ok, alice} = People.create_person(family, %{given_name: "Alice", surname: "A"})
      {:ok, bob} = People.create_person(family, %{given_name: "Bob", surname: "B"})

      people = People.list_people_for_family(family.id)
      graph = FamilyGraph.build(people, [])

      assert length(graph.unconnected) == 2
      assert graph.components == []
      ids = Enum.map(graph.unconnected, & &1.id) |> Enum.sort()
      assert ids == Enum.sort([alice.id, bob.id])
    end
  end

  describe "build/2 with a couple" do
    test "partner relationship creates a union and two person nodes" do
      family = family_fixture()
      {:ok, alice} = People.create_person(family, %{given_name: "Alice", surname: "A"})
      {:ok, bob} = People.create_person(family, %{given_name: "Bob", surname: "B"})
      {:ok, _rel} = Relationships.create_relationship(alice, bob, "partner")

      people = People.list_people_for_family(family.id)
      rels = Relationships.list_relationships_for_family(family.id)
      graph = FamilyGraph.build(people, rels)

      assert map_size(graph.nodes) == 2
      assert length(graph.unions) == 1
      assert graph.unconnected == []

      [union] = graph.unions
      assert union.type == :partner
      pair = Enum.sort([union.person_a_id, union.person_b_id])
      assert pair == Enum.sort([alice.id, bob.id])
    end
  end

  describe "build/2 with parent-child" do
    test "parent relationships create child edges from union" do
      family = family_fixture()
      {:ok, dad} = People.create_person(family, %{given_name: "Dad", surname: "D"})
      {:ok, mom} = People.create_person(family, %{given_name: "Mom", surname: "D"})
      {:ok, child} = People.create_person(family, %{given_name: "Kid", surname: "D"})
      {:ok, _} = Relationships.create_relationship(dad, mom, "partner")
      {:ok, _} = Relationships.create_relationship(dad, child, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mom, child, "parent", %{role: "mother"})

      people = People.list_people_for_family(family.id)
      rels = Relationships.list_relationships_for_family(family.id)
      graph = FamilyGraph.build(people, rels)

      assert map_size(graph.nodes) == 3
      assert length(graph.unions) == 1

      # child should be one generation below parents
      dad_node = graph.nodes[dad.id]
      child_node = graph.nodes[child.id]
      assert child_node.generation == dad_node.generation + 1
    end

    test "solo child (one known parent) creates solo child edge" do
      family = family_fixture()
      {:ok, parent} = People.create_person(family, %{given_name: "Parent", surname: "P"})
      {:ok, child} = People.create_person(family, %{given_name: "Child", surname: "C"})
      {:ok, _} = Relationships.create_relationship(parent, child, "parent", %{role: "mother"})

      people = People.list_people_for_family(family.id)
      rels = Relationships.list_relationships_for_family(family.id)
      graph = FamilyGraph.build(people, rels)

      assert map_size(graph.nodes) == 2
      assert graph.unions == []

      child_edges = graph.child_edges
      assert length(child_edges) == 1
      [edge] = child_edges
      assert edge.from == {:person, parent.id}
      assert edge.to == child.id
    end
  end

  describe "build/2 with ex-partners" do
    test "ex-partner creates a separate union" do
      family = family_fixture()
      {:ok, alice} = People.create_person(family, %{given_name: "Alice", surname: "A"})
      {:ok, bob} = People.create_person(family, %{given_name: "Bob", surname: "B"})
      {:ok, carol} = People.create_person(family, %{given_name: "Carol", surname: "C"})
      {:ok, _} = Relationships.create_relationship(alice, bob, "partner")
      {:ok, _} = Relationships.create_relationship(alice, carol, "ex_partner")

      people = People.list_people_for_family(family.id)
      rels = Relationships.list_relationships_for_family(family.id)
      graph = FamilyGraph.build(people, rels)

      assert map_size(graph.nodes) == 3
      assert length(graph.unions) == 2
      types = Enum.map(graph.unions, & &1.type) |> Enum.sort()
      assert types == [:ex_partner, :partner]
    end
  end

  describe "build/2 connected components" do
    test "disconnected families form separate components" do
      family = family_fixture()
      {:ok, alice} = People.create_person(family, %{given_name: "Alice", surname: "A"})
      {:ok, bob} = People.create_person(family, %{given_name: "Bob", surname: "B"})
      {:ok, carol} = People.create_person(family, %{given_name: "Carol", surname: "C"})
      {:ok, dave} = People.create_person(family, %{given_name: "Dave", surname: "D"})
      {:ok, _} = Relationships.create_relationship(alice, bob, "partner")
      {:ok, _} = Relationships.create_relationship(carol, dave, "partner")

      people = People.list_people_for_family(family.id)
      rels = Relationships.list_relationships_for_family(family.id)
      graph = FamilyGraph.build(people, rels)

      assert length(graph.components) == 2
    end
  end

  describe "build/2 generation assignment" do
    test "three-generation family has correct generation numbers" do
      family = family_fixture()
      {:ok, grandpa} = People.create_person(family, %{given_name: "Grandpa", surname: "G"})
      {:ok, grandma} = People.create_person(family, %{given_name: "Grandma", surname: "G"})
      {:ok, dad} = People.create_person(family, %{given_name: "Dad", surname: "G"})
      {:ok, mom} = People.create_person(family, %{given_name: "Mom", surname: "M"})
      {:ok, child} = People.create_person(family, %{given_name: "Child", surname: "G"})

      {:ok, _} = Relationships.create_relationship(grandpa, grandma, "partner")
      {:ok, _} = Relationships.create_relationship(grandpa, dad, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(grandma, dad, "parent", %{role: "mother"})
      {:ok, _} = Relationships.create_relationship(dad, mom, "partner")
      {:ok, _} = Relationships.create_relationship(dad, child, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mom, child, "parent", %{role: "mother"})

      people = People.list_people_for_family(family.id)
      rels = Relationships.list_relationships_for_family(family.id)
      graph = FamilyGraph.build(people, rels)

      assert graph.nodes[grandpa.id].generation == 0
      assert graph.nodes[grandma.id].generation == 0
      assert graph.nodes[dad.id].generation == 1
      assert graph.nodes[mom.id].generation == 1
      assert graph.nodes[child.id].generation == 2
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ancestry/people/family_graph_test.exs --seed 0 2>&1 | tail -10`
Expected: Compilation error — `Ancestry.People.FamilyGraph` module not found.

**Step 3: Write the FamilyGraph module**

Create `lib/ancestry/people/family_graph.ex`:

```elixir
defmodule Ancestry.People.FamilyGraph do
  @moduledoc """
  Builds a family graph from people and relationships.

  Uses Erlang's :digraph to model relationships, detect connected components,
  and assign generational layers. Outputs a struct with person nodes, union
  connectors, child edges, connected components, and unconnected people.
  """

  alias Ancestry.People.Person

  defstruct nodes: %{},
            unions: [],
            child_edges: [],
            components: [],
            unconnected: []

  defmodule Node do
    @moduledoc false
    defstruct [:person, :generation]
  end

  defmodule Union do
    @moduledoc false
    defstruct [:person_a_id, :person_b_id, :type, :id]
  end

  defmodule ChildEdge do
    @moduledoc false
    defstruct [:from, :to]
  end

  @doc """
  Builds a FamilyGraph from a list of people and relationships.

  Returns a `%FamilyGraph{}` with:
  - `nodes` — map of person_id => %Node{person, generation}
  - `unions` — list of %Union{} for partner/ex_partner relationships
  - `child_edges` — list of %ChildEdge{from, to} where from is {:union, id} or {:person, id}
  - `components` — list of lists of person_ids (connected subgraphs)
  - `unconnected` — list of %Person{} with no relationships
  """
  def build(people, relationships) do
    if people == [] do
      %__MODULE__{}
    else
      do_build(people, relationships)
    end
  end

  defp do_build(people, relationships) do
    people_by_id = Map.new(people, &{&1.id, &1})

    # Separate relationship types
    parent_rels = Enum.filter(relationships, &(&1.type == "parent"))
    partner_rels = Enum.filter(relationships, &(&1.type in ~w(partner ex_partner)))

    # Build unions from partner/ex_partner relationships
    unions =
      partner_rels
      |> Enum.with_index()
      |> Enum.map(fn {rel, idx} ->
        %Union{
          id: idx,
          person_a_id: rel.person_a_id,
          person_b_id: rel.person_b_id,
          type: String.to_existing_atom(rel.type)
        }
      end)

    # Build a lookup: for each child, find their parent IDs
    child_parents = build_child_parents_map(parent_rels)

    # Build child edges: connect children to unions or solo parents
    child_edges = build_child_edges(child_parents, unions)

    # Find people involved in any relationship
    involved_ids = find_involved_ids(relationships)

    # Split into connected vs unconnected
    {connected_people, unconnected_people} =
      Enum.split_with(people, &MapSet.member?(involved_ids, &1.id))

    # Build digraph for connected components and generation assignment
    {components, generations} =
      if connected_people == [] do
        {[], %{}}
      else
        compute_components_and_generations(
          connected_people,
          unions,
          child_edges,
          parent_rels
        )
      end

    # Build person nodes with generation info
    nodes =
      connected_people
      |> Map.new(fn person ->
        {person.id,
         %Node{
           person: person,
           generation: Map.get(generations, person.id, 0)
         }}
      end)

    %__MODULE__{
      nodes: nodes,
      unions: unions,
      child_edges: child_edges,
      components: components,
      unconnected: unconnected_people
    }
  end

  defp build_child_parents_map(parent_rels) do
    Enum.reduce(parent_rels, %{}, fn rel, acc ->
      # In parent relationships, person_a is parent, person_b is child
      child_id = rel.person_b_id
      parent_id = rel.person_a_id
      Map.update(acc, child_id, [parent_id], &[parent_id | &1])
    end)
  end

  defp build_child_edges(child_parents, unions) do
    Enum.flat_map(child_parents, fn {child_id, parent_ids} ->
      case parent_ids do
        [parent_a, parent_b] ->
          # Find the union that contains both parents
          case find_union_for_pair(unions, parent_a, parent_b) do
            nil ->
              # No union found — create solo edges from each parent
              [
                %ChildEdge{from: {:person, parent_a}, to: child_id},
                %ChildEdge{from: {:person, parent_b}, to: child_id}
              ]

            union ->
              [%ChildEdge{from: {:union, union.id}, to: child_id}]
          end

        [single_parent] ->
          [%ChildEdge{from: {:person, single_parent}, to: child_id}]
      end
    end)
  end

  defp find_union_for_pair(unions, parent_a, parent_b) do
    pair = Enum.sort([parent_a, parent_b])

    Enum.find(unions, fn union ->
      Enum.sort([union.person_a_id, union.person_b_id]) == pair
    end)
  end

  defp find_involved_ids(relationships) do
    relationships
    |> Enum.flat_map(fn rel -> [rel.person_a_id, rel.person_b_id] end)
    |> MapSet.new()
  end

  defp compute_components_and_generations(people, unions, child_edges, parent_rels) do
    g = :digraph.new([:acyclic])

    try do
      people_ids = Enum.map(people, & &1.id)

      # Add all person vertices
      for id <- people_ids, do: :digraph.add_vertex(g, {:person, id})

      # Add union vertices and edges to their members
      for union <- unions do
        :digraph.add_vertex(g, {:union, union.id})
        # Undirected: add edges both ways for component detection
        :digraph.add_edge(g, {:person, union.person_a_id}, {:union, union.id})
        :digraph.add_edge(g, {:union, union.id}, {:person, union.person_a_id})
        :digraph.add_edge(g, {:person, union.person_b_id}, {:union, union.id})
        :digraph.add_edge(g, {:union, union.id}, {:person, union.person_b_id})
      end

      # Add child edges (directed for generation, but also reverse for components)
      for edge <- child_edges do
        :digraph.add_edge(g, edge.from, {:person, edge.to})
        :digraph.add_edge(g, {:person, edge.to}, edge.from)
      end

      # Find connected components using reachability
      components = find_components(g, people_ids)

      # Compute generations using parent relationships
      generations = compute_generations(people_ids, parent_rels)

      {components, generations}
    after
      :digraph.delete(g)
    end
  end

  defp find_components(g, people_ids) do
    # BFS-based component detection
    remaining = MapSet.new(people_ids)

    find_components_loop(g, remaining, [])
  end

  defp find_components_loop(_g, remaining, components) when remaining == %MapSet{} do
    Enum.reverse(components)
  end

  defp find_components_loop(g, remaining, components) do
    if MapSet.size(remaining) == 0 do
      Enum.reverse(components)
    else
      start = remaining |> Enum.at(0)
      # Find all reachable person vertices from this start
      reachable = :digraph_utils.reachable([{:person, start}], g)

      component_ids =
        reachable
        |> Enum.flat_map(fn
          {:person, id} -> [id]
          _ -> []
        end)

      remaining = MapSet.difference(remaining, MapSet.new(component_ids))
      find_components_loop(g, remaining, [component_ids | components])
    end
  end

  defp compute_generations(people_ids, parent_rels) do
    # Build child -> parents lookup
    child_to_parents =
      Enum.reduce(parent_rels, %{}, fn rel, acc ->
        Map.update(acc, rel.person_b_id, [rel.person_a_id], &[rel.person_a_id | &1])
      end)

    # Build parent -> children lookup
    parent_to_children =
      Enum.reduce(parent_rels, %{}, fn rel, acc ->
        Map.update(acc, rel.person_a_id, [rel.person_b_id], &[rel.person_b_id | &1])
      end)

    # Find roots: people who are not children of anyone (in this family)
    all_ids = MapSet.new(people_ids)
    children_ids = child_to_parents |> Map.keys() |> MapSet.new()
    root_ids = MapSet.difference(all_ids, children_ids) |> MapSet.to_list()

    # BFS from roots to assign generations
    bfs_generations(root_ids, parent_to_children, %{}, 0)
  end

  defp bfs_generations([], _parent_to_children, generations, _gen), do: generations

  defp bfs_generations(current_level, parent_to_children, generations, gen) do
    # Assign generation to all people at current level (skip if already assigned)
    generations =
      Enum.reduce(current_level, generations, fn id, acc ->
        Map.put_new(acc, id, gen)
      end)

    # Collect next level: all children of current level
    next_level =
      current_level
      |> Enum.flat_map(fn id -> Map.get(parent_to_children, id, []) end)
      |> Enum.uniq()
      # Only process children not yet assigned
      |> Enum.reject(&Map.has_key?(generations, &1))

    bfs_generations(next_level, parent_to_children, generations, gen + 1)
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/ancestry/people/family_graph_test.exs --seed 0 2>&1 | tail -10`
Expected: All tests pass.

**Step 5: Commit**

```
git add lib/ancestry/people/family_graph.ex test/ancestry/people/family_graph_test.exs
git commit -m "Add FamilyGraph module with digraph builder and generation assignment"
```

---

### Task 3: Add grid layout computation to FamilyGraph

Extend `FamilyGraph` to compute a 2D grid of cells from the node/union/edge data.

**Files:**
- Modify: `lib/ancestry/people/family_graph.ex`
- Test: `test/ancestry/people/family_graph_test.exs`

**Step 1: Write the failing tests**

Add to `test/ancestry/people/family_graph_test.exs`:

```elixir
describe "to_grid/1" do
  test "single couple produces a grid with person and union cells" do
    family = family_fixture()
    {:ok, alice} = People.create_person(family, %{given_name: "Alice", surname: "A"})
    {:ok, bob} = People.create_person(family, %{given_name: "Bob", surname: "B"})
    {:ok, _} = Relationships.create_relationship(alice, bob, "partner")

    people = People.list_people_for_family(family.id)
    rels = Relationships.list_relationships_for_family(family.id)
    graph = FamilyGraph.build(people, rels)
    grid = FamilyGraph.to_grid(graph)

    assert grid.rows >= 1
    assert grid.cols >= 3

    # Should have exactly 2 person cells and 1 union cell
    person_cells =
      grid.cells
      |> Enum.filter(fn {_pos, cell} -> cell.type == :person end)

    union_cells =
      grid.cells
      |> Enum.filter(fn {_pos, cell} -> cell.type == :union end)

    assert length(person_cells) == 2
    assert length(union_cells) == 1
  end

  test "couple with one child produces connector cells" do
    family = family_fixture()
    {:ok, dad} = People.create_person(family, %{given_name: "Dad", surname: "D"})
    {:ok, mom} = People.create_person(family, %{given_name: "Mom", surname: "D"})
    {:ok, child} = People.create_person(family, %{given_name: "Kid", surname: "D"})
    {:ok, _} = Relationships.create_relationship(dad, mom, "partner")
    {:ok, _} = Relationships.create_relationship(dad, child, "parent", %{role: "father"})
    {:ok, _} = Relationships.create_relationship(mom, child, "parent", %{role: "mother"})

    people = People.list_people_for_family(family.id)
    rels = Relationships.list_relationships_for_family(family.id)
    graph = FamilyGraph.build(people, rels)
    grid = FamilyGraph.to_grid(graph)

    # Should have at least 2 rows (parents + child)
    assert grid.rows >= 2

    # Should have 3 person cells (dad, mom, child)
    person_cells =
      grid.cells
      |> Enum.filter(fn {_pos, cell} -> cell.type == :person end)

    assert length(person_cells) == 3

    # Should have at least one vertical connector
    v_cells =
      grid.cells
      |> Enum.filter(fn {_pos, cell} -> cell.type == :vertical end)

    assert length(v_cells) >= 1
  end

  test "ex-partner chain produces correct number of unions" do
    family = family_fixture()
    {:ok, alice} = People.create_person(family, %{given_name: "Alice", surname: "A"})
    {:ok, bob} = People.create_person(family, %{given_name: "Bob", surname: "B"})
    {:ok, carol} = People.create_person(family, %{given_name: "Carol", surname: "C"})
    {:ok, _} = Relationships.create_relationship(alice, bob, "partner")
    {:ok, _} = Relationships.create_relationship(bob, carol, "ex_partner")

    people = People.list_people_for_family(family.id)
    rels = Relationships.list_relationships_for_family(family.id)
    graph = FamilyGraph.build(people, rels)
    grid = FamilyGraph.to_grid(graph)

    person_cells =
      grid.cells |> Enum.filter(fn {_pos, cell} -> cell.type == :person end)

    union_cells =
      grid.cells |> Enum.filter(fn {_pos, cell} -> cell.type == :union end)

    assert length(person_cells) == 3
    assert length(union_cells) == 2
  end

  test "disconnected components are stacked vertically" do
    family = family_fixture()
    {:ok, alice} = People.create_person(family, %{given_name: "Alice", surname: "A"})
    {:ok, bob} = People.create_person(family, %{given_name: "Bob", surname: "B"})
    {:ok, carol} = People.create_person(family, %{given_name: "Carol", surname: "C"})
    {:ok, dave} = People.create_person(family, %{given_name: "Dave", surname: "D"})
    {:ok, _} = Relationships.create_relationship(alice, bob, "partner")
    {:ok, _} = Relationships.create_relationship(carol, dave, "partner")

    people = People.list_people_for_family(family.id)
    rels = Relationships.list_relationships_for_family(family.id)
    graph = FamilyGraph.build(people, rels)
    grid = FamilyGraph.to_grid(graph)

    person_cells =
      grid.cells |> Enum.filter(fn {_pos, cell} -> cell.type == :person end)

    assert length(person_cells) == 4

    # Should use more than 1 row (stacked components)
    rows_used =
      grid.cells |> Enum.map(fn {{row, _col}, _cell} -> row end) |> Enum.uniq()

    assert length(rows_used) >= 2
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ancestry/people/family_graph_test.exs --seed 0 2>&1 | tail -10`
Expected: `** (UndefinedFunctionError) function Ancestry.People.FamilyGraph.to_grid/1 is undefined`

**Step 3: Write the grid layout implementation**

Add the following to `lib/ancestry/people/family_graph.ex`. Add the `Grid` and `Cell` structs at the top alongside the existing structs, and the `to_grid/1` function after `build/2`:

```elixir
# Add these structs after the existing defmodule blocks:

defmodule Grid do
  @moduledoc false
  defstruct [:rows, :cols, :cells]
end

defmodule Cell do
  @moduledoc false
  defstruct [:type, :data]
end

# Add this function after build/2:

@doc """
Converts a FamilyGraph into a 2D grid of cells for CSS grid rendering.

Returns a `%Grid{}` with:
- `rows` — total number of grid rows
- `cols` — total number of grid columns
- `cells` — map of `{row, col} => %Cell{type, data}` where type is one of:
  `:person`, `:union`, `:horizontal`, `:vertical`, `:t_down`, `:top_left`, `:top_right`, `:bottom_left`, `:bottom_right`
"""
def to_grid(%__MODULE__{} = graph) do
  if graph.components == [] do
    %Grid{rows: 0, cols: 0, cells: %{}}
  else
    # Layout each component independently, then stack vertically
    {cells, total_rows, max_cols} =
      graph.components
      |> Enum.reduce({%{}, 0, 0}, fn component_ids, {cells_acc, row_offset, max_cols} ->
        {component_cells, comp_rows, comp_cols} =
          layout_component(component_ids, graph)

        # Offset this component's rows
        shifted_cells =
          Map.new(component_cells, fn {{r, c}, cell} ->
            {{r + row_offset, c}, cell}
          end)

        {Map.merge(cells_acc, shifted_cells), row_offset + comp_rows, max(max_cols, comp_cols)}
      end)

    %Grid{rows: total_rows, cols: max_cols, cells: cells}
  end
end

defp layout_component(component_ids, graph) do
  component_set = MapSet.new(component_ids)

  # Get people in this component with their generations
  people_by_gen =
    component_ids
    |> Enum.map(&{&1, graph.nodes[&1]})
    |> Enum.group_by(fn {_id, node} -> node.generation end)
    |> Enum.sort_by(fn {gen, _} -> gen end)

  # Get unions in this component
  component_unions =
    Enum.filter(graph.unions, fn union ->
      MapSet.member?(component_set, union.person_a_id) and
        MapSet.member?(component_set, union.person_b_id)
    end)

  # Get child edges in this component
  component_child_edges =
    Enum.filter(graph.child_edges, fn edge ->
      MapSet.member?(component_set, edge.to)
    end)

  # Build partnership chains per generation
  # A chain is a sequence: [person, union, person, union, person, ...]
  chains_by_gen =
    people_by_gen
    |> Enum.map(fn {gen, people_with_nodes} ->
      people_ids = Enum.map(people_with_nodes, fn {id, _} -> id end)
      chains = build_partnership_chains(people_ids, component_unions)
      {gen, chains}
    end)

  # Assign column positions to each chain element
  # Each chain element gets a column: person=1col, union=1col
  {col_assignments, max_col} = assign_columns(chains_by_gen)

  # Build cells from column assignments
  cells = build_cells_from_assignments(col_assignments, graph)

  # Now add connector cells between generations
  gen_rows = build_gen_row_map(chains_by_gen)
  # Each generation takes 2 rows: one for the people, one for connectors below
  total_gen_rows = length(chains_by_gen)
  total_rows = total_gen_rows * 2 - 1

  # Re-map cells to use spaced rows (every other row)
  spaced_cells =
    Map.new(cells, fn {{row, col}, cell} ->
      {{row * 2, col}, cell}
    end)

  # Add vertical and branching connectors between parent unions and children
  connector_cells =
    build_connector_cells(
      component_child_edges,
      col_assignments,
      graph,
      gen_rows
    )

  all_cells = Map.merge(spaced_cells, connector_cells)

  {all_cells, total_rows, max_col}
end

defp build_partnership_chains(people_ids, unions) do
  people_set = MapSet.new(people_ids)

  # Find unions involving people in this generation
  relevant_unions =
    Enum.filter(unions, fn u ->
      MapSet.member?(people_set, u.person_a_id) and
        MapSet.member?(people_set, u.person_b_id)
    end)

  # Build adjacency: person -> [{union, other_person}]
  adjacency =
    Enum.reduce(relevant_unions, %{}, fn union, acc ->
      acc
      |> Map.update(union.person_a_id, [{union, union.person_b_id}], &[{union, union.person_b_id} | &1])
      |> Map.update(union.person_b_id, [{union, union.person_a_id}], &[{union, union.person_a_id} | &1])
    end)

  # Walk chains starting from endpoints (degree 1) or any unvisited node
  build_chains(people_ids, adjacency, relevant_unions)
end

defp build_chains(people_ids, adjacency, _unions) do
  visited = MapSet.new()

  # Find chain starting points: prefer endpoints (degree 1), then any unvisited
  {chains, _visited} =
    Enum.reduce(people_ids, {[], visited}, fn person_id, {chains, visited} ->
      if MapSet.member?(visited, person_id) do
        {chains, visited}
      else
        {chain, visited} = walk_chain(person_id, adjacency, visited)
        {[chain | chains], visited}
      end
    end)

  Enum.reverse(chains)
end

defp walk_chain(start_id, adjacency, visited) do
  visited = MapSet.put(visited, start_id)
  chain = [{:person, start_id}]

  walk_chain_step(start_id, adjacency, visited, chain)
end

defp walk_chain_step(current_id, adjacency, visited, chain) do
  neighbors = Map.get(adjacency, current_id, [])

  case Enum.find(neighbors, fn {_union, other_id} -> not MapSet.member?(visited, other_id) end) do
    nil ->
      {Enum.reverse(chain), visited}

    {union, next_id} ->
      visited = MapSet.put(visited, next_id)
      chain = [{:person, next_id}, {:union, union} | chain]
      walk_chain_step(next_id, adjacency, visited, chain)
  end
end

defp assign_columns(chains_by_gen) do
  # For each generation, lay out chains left to right with gaps between chains
  {col_map, max_col} =
    Enum.reduce(chains_by_gen, {%{}, 0}, fn {gen, chains}, {col_map, _max} ->
      {gen_map, gen_max} =
        Enum.reduce(chains, {%{}, 0}, fn chain, {map, col} ->
          {chain_map, next_col} =
            Enum.reduce(chain, {%{}, col}, fn element, {m, c} ->
              {Map.put(m, element, {gen, c}), c + 1}
            end)

          # Add gap between chains
          {Map.merge(map, chain_map), next_col + 1}
        end)

      {Map.merge(col_map, gen_map), max(gen_max, Map.get(col_map, :max, 0))}
    end)

  # Find actual max column
  actual_max =
    col_map
    |> Enum.map(fn {_key, {_row, col}} -> col end)
    |> Enum.max(fn -> 0 end)

  {col_map, actual_max + 1}
end

defp build_cells_from_assignments(col_assignments, graph) do
  Enum.reduce(col_assignments, %{}, fn
    {{:person, person_id}, {gen_idx, col}}, cells ->
      node = graph.nodes[person_id]

      Map.put(cells, {gen_idx, col}, %Cell{
        type: :person,
        data: %{person: node.person, person_id: person_id}
      })

    {{:union, union}, {gen_idx, col}}, cells ->
      Map.put(cells, {gen_idx, col}, %Cell{
        type: :union,
        data: %{union: union}
      })
  end)
end

defp build_gen_row_map(chains_by_gen) do
  chains_by_gen
  |> Enum.with_index()
  |> Map.new(fn {{gen, _chains}, idx} -> {gen, idx} end)
end

defp build_connector_cells(child_edges, col_assignments, graph, gen_rows) do
  Enum.reduce(child_edges, %{}, fn edge, cells ->
    # Find the column of the source (union or person)
    source_pos = Map.get(col_assignments, edge.from)
    child_node = graph.nodes[edge.to]

    if source_pos && child_node do
      {source_gen_idx, source_col} = source_pos
      child_pos = Map.get(col_assignments, {:person, edge.to})

      if child_pos do
        {_child_gen_idx, child_col} = child_pos

        # The connector row is between the two generation rows
        connector_row = source_gen_idx * 2 + 1

        # Add vertical connector from source down
        cells = Map.put(cells, {connector_row, source_col}, %Cell{type: :vertical, data: %{}})

        # If child is not directly below, add horizontal connectors
        if child_col != source_col do
          min_col = min(source_col, child_col)
          max_col = max(source_col, child_col)

          # Add horizontal connectors
          Enum.reduce((min_col + 1)..(max_col - 1)//1, cells, fn col, acc ->
            Map.put_new(acc, {connector_row, col}, %Cell{type: :horizontal, data: %{}})
          end)
          |> Map.put(
            {connector_row, source_col},
            %Cell{type: :t_down, data: %{}}
          )
          |> Map.put(
            {connector_row, child_col},
            if(child_col < source_col,
              do: %Cell{type: :bottom_right, data: %{}},
              else: %Cell{type: :bottom_left, data: %{}}
            )
          )
        else
          cells
        end
      else
        cells
      end
    else
      cells
    end
  end)
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/ancestry/people/family_graph_test.exs --seed 0 2>&1 | tail -10`
Expected: All tests pass.

**Step 5: Commit**

```
git add lib/ancestry/people/family_graph.ex test/ancestry/people/family_graph_test.exs
git commit -m "Add grid layout computation to FamilyGraph"
```

---

### Task 4: Add `build_family_graph/1` to People context

**Files:**
- Modify: `lib/ancestry/people.ex`
- Test: `test/ancestry/people_test.exs`

**Step 1: Write the failing test**

Add to `test/ancestry/people_test.exs`:

```elixir
describe "build_family_graph/1" do
  test "returns a FamilyGraph struct" do
    family = family_fixture()
    {:ok, _} = People.create_person(family, %{given_name: "Alice", surname: "A"})

    graph = People.build_family_graph(family.id)
    assert %Ancestry.People.FamilyGraph{} = graph
  end

  test "includes people and relationships from the family" do
    family = family_fixture()
    {:ok, alice} = People.create_person(family, %{given_name: "Alice", surname: "A"})
    {:ok, bob} = People.create_person(family, %{given_name: "Bob", surname: "B"})
    {:ok, _} = Ancestry.Relationships.create_relationship(alice, bob, "partner")

    graph = People.build_family_graph(family.id)
    assert map_size(graph.nodes) == 2
    assert length(graph.unions) == 1
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ancestry/people_test.exs --seed 0 2>&1 | tail -10`
Expected: `** (UndefinedFunctionError) function Ancestry.People.build_family_graph/1 is undefined`

**Step 3: Write minimal implementation**

Add to `lib/ancestry/people.ex` (after `list_people_for_family/1`):

```elixir
alias Ancestry.People.FamilyGraph
alias Ancestry.Relationships

def build_family_graph(family_id) do
  people = list_people_for_family(family_id)
  relationships = Relationships.list_relationships_for_family(family_id)
  FamilyGraph.build(people, relationships)
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/ancestry/people_test.exs --seed 0 2>&1 | tail -10`
Expected: All tests pass.

**Step 5: Commit**

```
git add lib/ancestry/people.ex test/ancestry/people_test.exs
git commit -m "Add build_family_graph/1 to People context"
```

---

### Task 5: Create presentation LiveComponents

Create all the presentation LiveComponents. These are stateless components that receive data via assigns and render HTML/CSS.

**Files:**
- Create: `lib/web/live/family_live/canvas_component.ex`
- Create: `lib/web/live/family_live/tree_component.ex`
- Create: `lib/web/live/family_live/person_card_component.ex`
- Create: `lib/web/live/family_live/union_connector_component.ex`
- Create: `lib/web/live/family_live/connector_cell_component.ex`
- Create: `lib/web/live/family_live/side_panel_component.ex`
- Create: `lib/web/live/family_live/gallery_list_component.ex`
- Create: `lib/web/live/family_live/people_list_component.ex`

**Important learnings to apply:**
- From `docs/learnings.md`: "Reusable components should not embed navigation behavior." — PersonCardComponent should NOT wrap content in `<.link navigate>`. It should render a `<div>`, and the parent decides whether to wrap it in a link.
- From `docs/learnings.md`: "LiveComponent IDs must be stable when the component should persist." — Use stable IDs for all components (e.g., `id="canvas"`, `id="side-panel"`).

**Step 1: Create PersonCardComponent**

Create `lib/web/live/family_live/person_card_component.ex`:

```elixir
defmodule Web.FamilyLive.PersonCardComponent do
  use Web, :live_component

  alias Ancestry.People.Person

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="flex flex-col items-center text-center w-28">
      <div class="w-14 h-14 rounded-full bg-primary/10 flex items-center justify-center overflow-hidden mb-1">
        <%= if @person.photo && @person.photo_status == "processed" do %>
          <img
            src={Ancestry.Uploaders.PersonPhoto.url({@person.photo, @person}, :thumbnail)}
            alt={Person.display_name(@person)}
            class="w-full h-full object-cover"
          />
        <% else %>
          <.icon name="hero-user" class="w-7 h-7 text-primary" />
        <% end %>
      </div>
      <p class="text-xs font-medium text-base-content truncate w-full">
        {Person.display_name(@person)}
      </p>
      <%= if @person.birth_year do %>
        <p class="text-[10px] text-base-content/50">
          {format_life_span(@person)}
        </p>
      <% end %>
    </div>
    """
  end

  defp format_life_span(person) do
    birth = person.birth_year
    death = if person.deceased, do: person.death_year || "?", else: nil

    case {birth, death} do
      {nil, _} -> ""
      {b, nil} -> "#{b}"
      {b, d} -> "#{b}–#{d}"
    end
  end
end
```

**Step 2: Create UnionConnectorComponent**

Create `lib/web/live/family_live/union_connector_component.ex`:

```elixir
defmodule Web.FamilyLive.UnionConnectorComponent do
  use Web, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="flex items-center justify-center h-full">
      <div class={[
        "w-full h-0.5",
        if(@type == :partner,
          do: "bg-zinc-300 dark:bg-zinc-600",
          else: "bg-zinc-300/50 dark:bg-zinc-600/50 border-dashed"
        )
      ]}>
      </div>
    </div>
    """
  end
end
```

**Step 3: Create ConnectorCellComponent**

Create `lib/web/live/family_live/connector_cell_component.ex`:

```elixir
defmodule Web.FamilyLive.ConnectorCellComponent do
  use Web, :live_component

  @connector_color "border-zinc-300 dark:border-zinc-600"

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :connector_color, @connector_color)

    ~H"""
    <div id={@id} class="relative w-full h-full min-h-[2rem]">
      <div class={connector_classes(@type, @connector_color)}></div>
    </div>
    """
  end

  defp connector_classes(:vertical, color),
    do: "absolute left-1/2 top-0 bottom-0 #{color} border-l-2"

  defp connector_classes(:horizontal, color),
    do: "absolute top-1/2 left-0 right-0 #{color} border-t-2"

  defp connector_classes(:t_down, color),
    do: "absolute top-1/2 left-0 right-0 #{color} border-t-2 after:absolute after:left-1/2 after:top-0 after:bottom-0 after:#{color} after:border-l-2"

  defp connector_classes(:top_left, color),
    do: "absolute top-1/2 left-0 right-1/2 #{color} border-t-2 border-r-2 h-1/2"

  defp connector_classes(:top_right, color),
    do: "absolute top-1/2 left-1/2 right-0 #{color} border-t-2 border-l-2 h-1/2"

  defp connector_classes(:bottom_left, color),
    do: "absolute bottom-1/2 left-0 right-1/2 #{color} border-b-2 border-r-2 h-1/2"

  defp connector_classes(:bottom_right, color),
    do: "absolute bottom-1/2 left-1/2 right-0 #{color} border-b-2 border-l-2 h-1/2"

  defp connector_classes(_, _color), do: ""
end
```

**Step 4: Create TreeComponent**

Create `lib/web/live/family_live/tree_component.ex`:

```elixir
defmodule Web.FamilyLive.TreeComponent do
  use Web, :live_component

  alias Web.FamilyLive.PersonCardComponent
  alias Web.FamilyLive.UnionConnectorComponent
  alias Web.FamilyLive.ConnectorCellComponent

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id={@id}
      class="family-tree-grid"
      style={"grid-template-columns: repeat(#{@grid.cols}, minmax(8rem, 1fr)); grid-template-rows: repeat(#{@grid.rows}, auto);"}
    >
      <%= for row <- 0..(@grid.rows - 1), col <- 0..(@grid.cols - 1) do %>
        <% cell = Map.get(@grid.cells, {row, col}) %>
        <%= if cell do %>
          <%= case cell.type do %>
            <% :person -> %>
              <div style={"grid-row: #{row + 1}; grid-column: #{col + 1};"} class="flex items-center justify-center p-2">
                <.link navigate={~p"/families/#{@family_id}/members/#{cell.data.person_id}"}>
                  <.live_component
                    module={PersonCardComponent}
                    id={"person-card-#{cell.data.person_id}"}
                    person={cell.data.person}
                  />
                </.link>
              </div>
            <% :union -> %>
              <div style={"grid-row: #{row + 1}; grid-column: #{col + 1};"} class="flex items-center justify-center p-1">
                <.live_component
                  module={UnionConnectorComponent}
                  id={"union-#{cell.data.union.id}"}
                  type={cell.data.union.type}
                />
              </div>
            <% connector_type -> %>
              <div style={"grid-row: #{row + 1}; grid-column: #{col + 1};"}>
                <.live_component
                  module={ConnectorCellComponent}
                  id={"connector-#{row}-#{col}"}
                  type={connector_type}
                />
              </div>
          <% end %>
        <% end %>
      <% end %>
    </div>
    """
  end
end
```

**Step 5: Create CanvasComponent**

Create `lib/web/live/family_live/canvas_component.ex`:

```elixir
defmodule Web.FamilyLive.CanvasComponent do
  use Web, :live_component

  alias Ancestry.People.Person
  alias Web.FamilyLive.TreeComponent

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="overflow-auto flex-1 min-h-0 p-4">
      <%= if @graph.components != [] do %>
        <%= for {component_ids, idx} <- Enum.with_index(@graph.components) do %>
          <.live_component
            module={TreeComponent}
            id={"tree-#{idx}"}
            grid={@grid}
            family_id={@family_id}
          />
        <% end %>
      <% end %>

      <%= if @graph.unconnected != [] do %>
        <div class="mt-8">
          <h3 class="text-sm font-medium text-base-content/40 mb-3">Not connected to tree</h3>
          <div class="flex flex-wrap gap-4 lg:flex-row flex-col">
            <%= for person <- @graph.unconnected do %>
              <.link navigate={~p"/families/#{@family_id}/members/#{person.id}"}>
                <div class="flex items-center gap-2 px-3 py-2 rounded-lg bg-base-200/50 hover:bg-base-200 transition-colors">
                  <div class="w-8 h-8 rounded-full bg-primary/10 flex items-center justify-center overflow-hidden">
                    <%= if person.photo && person.photo_status == "processed" do %>
                      <img
                        src={Ancestry.Uploaders.PersonPhoto.url({person.photo, person}, :thumbnail)}
                        alt={Person.display_name(person)}
                        class="w-full h-full object-cover"
                      />
                    <% else %>
                      <.icon name="hero-user" class="w-4 h-4 text-primary" />
                    <% end %>
                  </div>
                  <span class="text-sm text-base-content">{Person.display_name(person)}</span>
                </div>
              </.link>
            <% end %>
          </div>
        </div>
      <% end %>

      <%= if @graph.components == [] and @graph.unconnected == [] do %>
        <div class="flex items-center justify-center h-48 text-base-content/40">
          No members yet. Add members from the side panel.
        </div>
      <% end %>
    </div>
    """
  end
end
```

**Step 6: Create GalleryListComponent**

Create `lib/web/live/family_live/gallery_list_component.ex`:

```elixir
defmodule Web.FamilyLive.GalleryListComponent do
  use Web, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <div class="flex items-center justify-between mb-3">
        <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider">Galleries</h3>
        <button
          id="open-new-gallery-btn"
          phx-click="open_new_gallery_modal"
          class="p-1 rounded text-base-content/40 hover:text-primary hover:bg-primary/10 transition-colors"
        >
          <.icon name="hero-plus" class="w-4 h-4" />
        </button>
      </div>
      <div
        id="galleries"
        phx-update="stream"
        class="space-y-1"
      >
        <div
          id="galleries-empty"
          class="hidden only:block text-sm text-base-content/40 py-2"
        >
          No galleries yet.
        </div>
        <.link
          :for={{id, gallery} <- @streams.galleries}
          id={id}
          navigate={~p"/families/#{@family_id}/galleries/#{gallery.id}"}
          class="flex items-center gap-2 px-2 py-1.5 rounded-lg hover:bg-base-200 transition-colors text-sm text-base-content"
        >
          <.icon name="hero-photo" class="w-4 h-4 text-base-content/40" />
          <span class="truncate" data-gallery-name>{gallery.name}</span>
        </.link>
      </div>
    </div>
    """
  end
end
```

**Step 7: Create PeopleListComponent**

Create `lib/web/live/family_live/people_list_component.ex`:

```elixir
defmodule Web.FamilyLive.PeopleListComponent do
  use Web, :live_component

  alias Ancestry.People.Person

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <div class="flex items-center justify-between mb-3">
        <h3 class="text-sm font-semibold text-base-content/60 uppercase tracking-wider">People</h3>
        <div class="flex items-center gap-1">
          <button
            id="link-existing-btn"
            phx-click="open_search"
            class="p-1 rounded text-base-content/40 hover:text-primary hover:bg-primary/10 transition-colors"
            title="Link existing person"
          >
            <.icon name="hero-magnifying-glass" class="w-4 h-4" />
          </button>
          <.link
            id="add-member-btn"
            navigate={~p"/families/#{@family_id}/members/new"}
            class="p-1 rounded text-base-content/40 hover:text-primary hover:bg-primary/10 transition-colors"
            title="New member"
          >
            <.icon name="hero-plus" class="w-4 h-4" />
          </.link>
        </div>
      </div>

      <div class="mb-3">
        <input
          id="people-filter-input"
          type="text"
          placeholder="Filter people..."
          class="input input-bordered input-sm w-full"
          phx-hook="FuzzyFilter"
          data-target="people-list"
        />
      </div>

      <div id="people-list" class="space-y-0.5 max-h-96 overflow-y-auto">
        <%= if @people == [] do %>
          <p class="text-sm text-base-content/40 py-2">No members yet.</p>
        <% end %>
        <%= for person <- @people do %>
          <.link
            navigate={~p"/families/#{@family_id}/members/#{person.id}"}
            class="flex items-center gap-2 px-2 py-1.5 rounded-lg hover:bg-base-200 transition-colors text-sm"
            data-filter-name={"#{person.surname}, #{person.given_name}" |> String.downcase()}
          >
            <div class="w-6 h-6 rounded-full bg-primary/10 flex items-center justify-center overflow-hidden flex-shrink-0">
              <%= if person.photo && person.photo_status == "processed" do %>
                <img
                  src={Ancestry.Uploaders.PersonPhoto.url({person.photo, person}, :thumbnail)}
                  alt={Person.display_name(person)}
                  class="w-full h-full object-cover"
                />
              <% else %>
                <.icon name="hero-user" class="w-3 h-3 text-primary" />
              <% end %>
            </div>
            <span class="text-base-content truncate">
              {person.surname}<%= if person.surname && person.given_name do %>,<% end %> {person.given_name}
            </span>
          </.link>
        <% end %>
      </div>
    </div>
    """
  end
end
```

**Step 8: Create SidePanelComponent**

Create `lib/web/live/family_live/side_panel_component.ex`:

```elixir
defmodule Web.FamilyLive.SidePanelComponent do
  use Web, :live_component

  alias Web.FamilyLive.GalleryListComponent
  alias Web.FamilyLive.PeopleListComponent

  @impl true
  def render(assigns) do
    ~H"""
    <aside id={@id} class="w-72 border-l border-base-200 bg-base-100 flex flex-col overflow-y-auto p-4 gap-6 lg:w-72 max-lg:w-full max-lg:border-l-0 max-lg:border-t">
      <.live_component
        module={GalleryListComponent}
        id="gallery-list"
        streams={@streams}
        family_id={@family_id}
      />

      <div class="border-t border-base-200"></div>

      <.live_component
        module={PeopleListComponent}
        id="people-list"
        people={@people}
        family_id={@family_id}
      />
    </aside>
    """
  end
end
```

**Step 9: Commit**

```
git add lib/web/live/family_live/person_card_component.ex \
  lib/web/live/family_live/union_connector_component.ex \
  lib/web/live/family_live/connector_cell_component.ex \
  lib/web/live/family_live/tree_component.ex \
  lib/web/live/family_live/canvas_component.ex \
  lib/web/live/family_live/gallery_list_component.ex \
  lib/web/live/family_live/people_list_component.ex \
  lib/web/live/family_live/side_panel_component.ex
git commit -m "Add presentation LiveComponents for family tree canvas"
```

---

### Task 6: Add FuzzyFilter JS hook for client-side people filtering

**Files:**
- Modify: `assets/js/app.js`

**Step 1: Add the FuzzyFilter hook**

Add to `assets/js/app.js` before the `let liveSocket = new LiveSocket(...)` line:

```javascript
const FuzzyFilter = {
  mounted() {
    const targetId = this.el.dataset.target
    this.el.addEventListener("input", (e) => {
      const query = e.target.value.toLowerCase().trim()
      const container = document.getElementById(targetId)
      if (!container) return

      const items = container.querySelectorAll("[data-filter-name]")
      items.forEach((item) => {
        const name = item.dataset.filterName
        if (!query || name.includes(query)) {
          item.style.display = ""
        } else {
          item.style.display = "none"
        }
      })
    })
  }
}
```

Then add `FuzzyFilter` to the hooks object passed to `LiveSocket`:

```javascript
let liveSocket = new LiveSocket("/live", Socket, {
  // ... existing params ...
  hooks: { ...existingHooks, FuzzyFilter }
})
```

**Step 2: Commit**

```
git add assets/js/app.js
git commit -m "Add FuzzyFilter JS hook for client-side people list filtering"
```

---

### Task 7: Add CSS for family tree grid

**Files:**
- Modify: `assets/css/app.css`

**Step 1: Add the family tree grid styles**

Add to `assets/css/app.css`:

```css
.family-tree-grid {
  display: grid;
  gap: 0;
  justify-items: center;
  align-items: center;
}
```

**Step 2: Commit**

```
git add assets/css/app.css
git commit -m "Add CSS for family tree grid layout"
```

---

### Task 8: Rewrite FamilyLive.Show to use new layout

This replaces the current page layout with the two-panel (canvas + side panel) design. All existing event handlers stay intact — only the mount and template change.

**Files:**
- Modify: `lib/web/live/family_live/show.ex`
- Rewrite: `lib/web/live/family_live/show.html.heex`

**Step 1: Update mount in show.ex**

Replace the mount function in `lib/web/live/family_live/show.ex` to build the family graph:

```elixir
@impl true
def mount(%{"family_id" => family_id}, _session, socket) do
  family = Families.get_family!(family_id)

  if connected?(socket) do
    Phoenix.PubSub.subscribe(Ancestry.PubSub, "family:#{family_id}")
  end

  graph = People.build_family_graph(family_id)
  grid = Ancestry.People.FamilyGraph.to_grid(graph)
  people = People.list_people_for_family(family_id)

  {:ok,
   socket
   |> assign(:family, family)
   |> assign(:graph, graph)
   |> assign(:grid, grid)
   |> assign(:people, people)
   |> assign(:editing, false)
   |> assign(:confirm_delete, false)
   |> assign(:form, to_form(Families.change_family(family)))
   |> assign(:show_new_gallery_modal, false)
   |> assign(:confirm_delete_gallery, nil)
   |> assign(:gallery_form, to_form(Galleries.change_gallery(%Gallery{})))
   |> assign(:search_mode, false)
   |> assign(:search_query, "")
   |> assign(:search_results, [])
   |> stream(:galleries, Galleries.list_galleries(family_id))}
end
```

Note: `:members` stream is removed — the people list in the side panel uses the `@people` assign, and the canvas uses `@graph`/`@grid`.

**Step 2: Update the `link_person` handler to refresh graph**

Update the `link_person` event handler to also rebuild the graph after linking a person:

```elixir
def handle_event("link_person", %{"id" => id}, socket) do
  person = People.get_person!(String.to_integer(id))
  family = socket.assigns.family

  case People.add_to_family(person, family) do
    {:ok, _} ->
      graph = People.build_family_graph(family.id)
      grid = Ancestry.People.FamilyGraph.to_grid(graph)
      people = People.list_people_for_family(family.id)

      {:noreply,
       socket
       |> assign(:graph, graph)
       |> assign(:grid, grid)
       |> assign(:people, people)
       |> assign(:search_mode, false)
       |> assign(:search_results, [])
       |> assign(:search_query, "")}

    {:error, _} ->
      {:noreply, socket}
  end
end
```

**Step 3: Rewrite the template**

Rewrite `lib/web/live/family_live/show.html.heex` with the new two-panel layout. Keep all existing modals at the bottom. The toolbar stays the same. The main content area becomes canvas + side panel:

```heex
<Layouts.app flash={@flash}>
  <:toolbar>
    <div class="max-w-full mx-auto flex items-center justify-between py-3 px-4">
      <div class="flex items-center gap-3">
        <.link
          navigate={~p"/"}
          class="p-2 rounded-lg text-base-content/40 hover:text-base-content hover:bg-base-200 transition-colors"
        >
          <.icon name="hero-arrow-left" class="w-5 h-5" />
        </.link>
        <h1 class="text-2xl font-bold text-base-content">{@family.name}</h1>
      </div>
      <div class="flex items-center gap-2">
        <button
          id="edit-family-btn"
          phx-click="edit"
          class="btn btn-ghost btn-sm"
        >
          <.icon name="hero-pencil" class="w-4 h-4" /> Edit
        </button>
        <button
          id="delete-family-btn"
          phx-click="request_delete"
          class="btn btn-ghost btn-sm text-error"
        >
          <.icon name="hero-trash" class="w-4 h-4" /> Delete
        </button>
      </div>
    </div>
  </:toolbar>

  <div class="flex flex-col lg:flex-row h-[calc(100vh-4rem)]">
    <%!-- Canvas area --%>
    <.live_component
      module={Web.FamilyLive.CanvasComponent}
      id="canvas"
      graph={@graph}
      grid={@grid}
      family_id={@family.id}
    />

    <%!-- Side panel --%>
    <.live_component
      module={Web.FamilyLive.SidePanelComponent}
      id="side-panel"
      streams={@streams}
      people={@people}
      family_id={@family.id}
    />
  </div>

  <%!-- Edit Family Modal --%>
  <%= if @editing do %>
    <div class="fixed inset-0 z-50 flex items-center justify-center">
      <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" phx-click="cancel_edit"></div>
      <div class="relative card bg-base-100 shadow-2xl w-full max-w-md mx-4 p-8">
        <h2 class="text-xl font-bold text-base-content mb-6">Edit Family</h2>
        <.form
          for={@form}
          id="edit-family-form"
          phx-submit="save"
          phx-change="validate"
        >
          <.input
            field={@form[:name]}
            label="Family name"
            autofocus
          />
          <div class="flex gap-3 mt-6">
            <button type="submit" class="btn btn-primary flex-1">Save</button>
            <button type="button" phx-click="cancel_edit" class="btn btn-ghost flex-1">
              Cancel
            </button>
          </div>
        </.form>
      </div>
    </div>
  <% end %>

  <%!-- Delete Family Confirmation Modal --%>
  <%= if @confirm_delete do %>
    <div class="fixed inset-0 z-50 flex items-center justify-center">
      <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" phx-click="cancel_delete"></div>
      <div
        id="confirm-delete-family-modal"
        class="relative card bg-base-100 shadow-2xl w-full max-w-md mx-4 p-8"
      >
        <h2 class="text-xl font-bold text-base-content mb-2">Delete Family</h2>
        <p class="text-base-content/60 mb-6">
          Delete <span class="font-semibold">"{@family.name}"</span>? All galleries and photos will be permanently removed. This cannot be undone.
        </p>
        <div class="flex gap-3">
          <button phx-click="confirm_delete" class="btn btn-error flex-1">Delete</button>
          <button phx-click="cancel_delete" class="btn btn-ghost flex-1">Cancel</button>
        </div>
      </div>
    </div>
  <% end %>

  <%!-- New Gallery Modal --%>
  <%= if @show_new_gallery_modal do %>
    <div class="fixed inset-0 z-50 flex items-center justify-center">
      <div
        class="absolute inset-0 bg-black/60 backdrop-blur-sm"
        phx-click="close_new_gallery_modal"
      >
      </div>
      <div
        id="new-gallery-modal"
        class="relative card bg-base-100 shadow-2xl w-full max-w-md mx-4 p-8"
      >
        <h2 class="text-xl font-bold text-base-content mb-6">New Gallery</h2>
        <.form
          for={@gallery_form}
          id="new-gallery-form"
          phx-submit="save_gallery"
          phx-change="validate_gallery"
        >
          <.input
            field={@gallery_form[:name]}
            label="Gallery name"
            placeholder="e.g. Summer 2025"
            autofocus
          />
          <div class="flex gap-3 mt-6">
            <button type="submit" class="btn btn-primary flex-1">Create</button>
            <button type="button" phx-click="close_new_gallery_modal" class="btn btn-ghost flex-1">
              Cancel
            </button>
          </div>
        </.form>
      </div>
    </div>
  <% end %>

  <%!-- Delete Gallery Confirmation Modal --%>
  <%= if @confirm_delete_gallery do %>
    <div class="fixed inset-0 z-50 flex items-center justify-center">
      <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" phx-click="cancel_delete_gallery">
      </div>
      <div
        id="confirm-delete-gallery-modal"
        class="relative card bg-base-100 shadow-2xl w-full max-w-md mx-4 p-8"
      >
        <h2 class="text-xl font-bold text-base-content mb-2">Delete Gallery</h2>
        <p class="text-base-content/60 mb-6">
          Delete <span class="font-semibold">"{@confirm_delete_gallery.name}"</span>? All photos will be permanently removed. This cannot be undone.
        </p>
        <div class="flex gap-3">
          <button phx-click="confirm_delete_gallery" class="btn btn-error flex-1">Delete</button>
          <button phx-click="cancel_delete_gallery" class="btn btn-ghost flex-1">Cancel</button>
        </div>
      </div>
    </div>
  <% end %>

  <%!-- Search/Link Existing Person Modal --%>
  <%= if @search_mode do %>
    <div class="fixed inset-0 z-50 flex items-center justify-center">
      <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" phx-click="close_search"></div>
      <div
        id="link-person-modal"
        class="relative card bg-base-100 shadow-2xl w-full max-w-md mx-4 p-8"
      >
        <h2 class="text-xl font-bold text-base-content mb-4">Link Existing Person</h2>
        <input
          id="person-search-input"
          type="text"
          name="query"
          value={@search_query}
          placeholder="Search by name..."
          phx-keyup="search"
          phx-debounce="300"
          autofocus
          class="input input-bordered w-full mb-4"
        />
        <div class="max-h-64 overflow-y-auto space-y-2">
          <%= if @search_results == [] && String.length(String.trim(@search_query)) >= 2 do %>
            <p class="text-base-content/40 text-sm text-center py-4">No results found</p>
          <% end %>
          <%= for person <- @search_results do %>
            <button
              id={"link-person-#{person.id}"}
              phx-click="link_person"
              phx-value-id={person.id}
              class="w-full flex items-center gap-3 p-3 rounded-lg hover:bg-base-200 transition-colors text-left"
            >
              <div class="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center flex-shrink-0 overflow-hidden">
                <%= if person.photo && person.photo_status == "processed" do %>
                  <img
                    src={Ancestry.Uploaders.PersonPhoto.url({person.photo, person}, :thumbnail)}
                    alt={Ancestry.People.Person.display_name(person)}
                    class="w-full h-full object-cover"
                  />
                <% else %>
                  <.icon name="hero-user" class="w-5 h-5 text-primary" />
                <% end %>
              </div>
              <div class="min-w-0">
                <p class="font-medium text-base-content truncate">
                  {Ancestry.People.Person.display_name(person)}
                </p>
                <%= if person.families != [] do %>
                  <p class="text-xs text-base-content/40 truncate">
                    {Enum.map_join(person.families, ", ", & &1.name)}
                  </p>
                <% end %>
              </div>
            </button>
          <% end %>
        </div>
        <button phx-click="close_search" class="btn btn-ghost w-full mt-4">Cancel</button>
      </div>
    </div>
  <% end %>
</Layouts.app>
```

**Step 4: Commit**

```
git add lib/web/live/family_live/show.ex lib/web/live/family_live/show.html.heex
git commit -m "Rewrite FamilyLive.Show with canvas + side panel layout"
```

---

### Task 9: Update existing tests

The existing `FamilyLive.ShowTest` tests need updating since the page layout changed. The members list now lives in the side panel with "surname, given_name" format, and some button IDs moved.

**Files:**
- Modify: `test/web/live/family_live/show_test.exs`

**Step 1: Update tests to match new layout**

Key changes:
- Members are no longer in a `#members` stream container — they're in `#people-list`
- The member names now display as "surname, given_name" in the people list
- Buttons moved: "Add Member" and "Link Existing" are now in the side panel
- Gallery buttons are in the side panel

Review each failing test and update selectors to match the new DOM structure. Specifically:

- `"shows family members"` — check for "Doe, Jane" in `#people-list` instead of "Jane Doe" in `#members`
- `"shows empty states"` — empty states text may have changed
- `"link_person"` tests — the `#link-existing-btn` still exists, same ID
- Gallery tests — `#open-new-gallery-btn` still exists, same ID

**Step 2: Run all tests**

Run: `mix test test/web/live/family_live/show_test.exs --seed 0 2>&1 | tail -20`
Fix any remaining failures.

**Step 3: Commit**

```
git add test/web/live/family_live/show_test.exs
git commit -m "Update FamilyLive.Show tests for new canvas layout"
```

---

### Task 10: Run precommit and fix issues

**Step 1: Run precommit**

Run: `mix precommit`

This runs compile (warnings-as-errors), unused deps, formatting, and tests.

**Step 2: Fix any issues**

Address any compilation warnings, formatting issues, or test failures.

**Step 3: Final commit**

```
git add -A
git commit -m "Fix code quality issues from precommit"
```

---

### Task 11: Manual visual verification

**Step 1: Start the dev server**

Run: `iex -S mix phx.server`

**Step 2: Import test data if not present**

If you have the CSV data: `mix ancestry.import_csv family.csv`

**Step 3: Verify visually**

Navigate to a family page. Check:
- Canvas renders tree with correct generational layout
- Partner/ex-partner chains display horizontally
- Connector lines render between generations
- Unconnected people show at bottom
- Side panel shows galleries and people lists
- Fuzzy search filters the people list
- "New Gallery", "New Member", "Link Existing" buttons work
- Scrolling works when tree is large
- Mobile layout stacks vertically

**Step 4: Fix any visual issues and commit**

```
git add -A
git commit -m "Polish family tree canvas visual presentation"
```
