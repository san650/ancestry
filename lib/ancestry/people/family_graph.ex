defmodule Ancestry.People.FamilyGraph do
  @moduledoc """
  Builds a family graph data structure from people and relationships.

  Takes a list of `%Person{}` structs and `%Relationship{}` structs, builds an
  Erlang `:digraph` for connected component detection, computes generations via
  BFS from root nodes, and returns a flat `%FamilyGraph{}` struct.
  """

  alias __MODULE__.ChildEdge
  alias __MODULE__.Node
  alias __MODULE__.Union

  defstruct nodes: %{},
            unions: [],
            child_edges: [],
            components: [],
            unconnected: []

  @doc """
  Build a family graph from a list of people and relationships.

  Returns a `%FamilyGraph{}` struct with nodes, unions, child edges,
  connected components, and unconnected people.
  """
  def build([], []), do: %__MODULE__{}

  def build(people, relationships) do
    {parent_rels, partner_rels} = separate_relationships(relationships)

    unions = build_unions(partner_rels)
    union_lookup = build_union_lookup(unions)

    child_parents = build_child_parents_map(parent_rels)
    child_edges = build_child_edges(child_parents, union_lookup)

    involved_ids = find_involved_ids(relationships)
    {connected_people, unconnected_people} = split_people(people, involved_ids)

    components = find_components(connected_people, unions, child_edges)
    generations = compute_generations(connected_people, parent_rels, partner_rels)

    nodes =
      Map.new(connected_people, fn person ->
        {person.id, %Node{person: person, generation: Map.get(generations, person.id, 0)}}
      end)

    %__MODULE__{
      nodes: nodes,
      unions: unions,
      child_edges: child_edges,
      components: components,
      unconnected: unconnected_people
    }
  end

  defp separate_relationships(relationships) do
    Enum.split_with(relationships, fn rel -> rel.type == "parent" end)
  end

  defp build_unions(partner_rels) do
    Enum.map(partner_rels, fn rel ->
      %Union{
        id: rel.id,
        person_a_id: rel.person_a_id,
        person_b_id: rel.person_b_id,
        type: String.to_existing_atom(rel.type)
      }
    end)
  end

  defp build_union_lookup(unions) do
    Enum.reduce(unions, %{}, fn union, acc ->
      key = union_key(union.person_a_id, union.person_b_id)
      Map.put(acc, key, union)
    end)
  end

  defp union_key(id_a, id_b) do
    {min(id_a, id_b), max(id_a, id_b)}
  end

  defp build_child_parents_map(parent_rels) do
    Enum.reduce(parent_rels, %{}, fn rel, acc ->
      Map.update(acc, rel.person_b_id, [rel.person_a_id], &[rel.person_a_id | &1])
    end)
  end

  defp build_child_edges(child_parents, union_lookup) do
    Enum.flat_map(child_parents, fn {child_id, parent_ids} ->
      case parent_ids do
        [parent_a, parent_b] ->
          key = union_key(parent_a, parent_b)

          case Map.get(union_lookup, key) do
            %Union{} = union ->
              [%ChildEdge{from: {:union, union.id}, to: child_id}]

            nil ->
              # Two parents but no union between them — solo edges from each
              [
                %ChildEdge{from: {:person, parent_a}, to: child_id},
                %ChildEdge{from: {:person, parent_b}, to: child_id}
              ]
          end

        [single_parent] ->
          [%ChildEdge{from: {:person, single_parent}, to: child_id}]

        parents ->
          Enum.map(parents, fn parent_id ->
            %ChildEdge{from: {:person, parent_id}, to: child_id}
          end)
      end
    end)
  end

  defp find_involved_ids(relationships) do
    Enum.reduce(relationships, MapSet.new(), fn rel, acc ->
      acc
      |> MapSet.put(rel.person_a_id)
      |> MapSet.put(rel.person_b_id)
    end)
  end

  defp split_people(people, involved_ids) do
    Enum.split_with(people, fn person -> MapSet.member?(involved_ids, person.id) end)
  end

  defp find_components([], _unions, _child_edges), do: []

  defp find_components(connected_people, unions, child_edges) do
    g = :digraph.new()

    try do
      # Add person vertices
      for person <- connected_people do
        :digraph.add_vertex(g, {:person, person.id})
      end

      # Add union vertices and bidirectional edges to their members
      for union <- unions do
        :digraph.add_vertex(g, {:union, union.id})
        :digraph.add_edge(g, {:person, union.person_a_id}, {:union, union.id})
        :digraph.add_edge(g, {:union, union.id}, {:person, union.person_a_id})
        :digraph.add_edge(g, {:person, union.person_b_id}, {:union, union.id})
        :digraph.add_edge(g, {:union, union.id}, {:person, union.person_b_id})
      end

      # Add child edges (bidirectional for component detection)
      for edge <- child_edges do
        from_vertex = edge.from
        to_vertex = {:person, edge.to}
        :digraph.add_edge(g, from_vertex, to_vertex)
        :digraph.add_edge(g, to_vertex, from_vertex)
      end

      # Find connected components via reachability
      person_vertices =
        Enum.map(connected_people, fn person -> {:person, person.id} end)

      find_reachable_components(g, person_vertices)
    after
      :digraph.delete(g)
    end
  end

  defp find_reachable_components(g, person_vertices) do
    find_reachable_components(g, person_vertices, MapSet.new(), [])
  end

  defp find_reachable_components(_g, [], _visited, components) do
    Enum.reverse(components)
  end

  defp find_reachable_components(g, [vertex | rest], visited, components) do
    if MapSet.member?(visited, vertex) do
      find_reachable_components(g, rest, visited, components)
    else
      # Find all vertices reachable from this one
      reachable = :digraph_utils.reachable([vertex], g)

      # Extract person IDs from reachable vertices
      person_ids =
        reachable
        |> Enum.filter(fn
          {:person, _} -> true
          _ -> false
        end)
        |> Enum.map(fn {:person, id} -> id end)

      # Mark all reachable person vertices as visited
      new_visited =
        Enum.reduce(reachable, visited, fn v, acc ->
          case v do
            {:person, _} -> MapSet.put(acc, v)
            _ -> acc
          end
        end)

      find_reachable_components(g, rest, new_visited, [person_ids | components])
    end
  end

  defp compute_generations([], _parent_rels, _partner_rels), do: %{}

  defp compute_generations(connected_people, parent_rels, partner_rels) do
    # Build child -> parents map from parent_rels
    child_to_parents =
      Enum.reduce(parent_rels, %{}, fn rel, acc ->
        Map.update(acc, rel.person_b_id, [rel.person_a_id], &[rel.person_a_id | &1])
      end)

    # Build parent -> children map
    parent_to_children =
      Enum.reduce(parent_rels, %{}, fn rel, acc ->
        Map.update(acc, rel.person_a_id, [rel.person_b_id], &[rel.person_b_id | &1])
      end)

    # Build partner map (bidirectional)
    partner_map =
      Enum.reduce(partner_rels, %{}, fn rel, acc ->
        acc
        |> Map.update(rel.person_a_id, [rel.person_b_id], &[rel.person_b_id | &1])
        |> Map.update(rel.person_b_id, [rel.person_a_id], &[rel.person_a_id | &1])
      end)

    all_ids = MapSet.new(connected_people, & &1.id)

    # Root nodes: people who are not children of anyone (within the connected set)
    children_ids = MapSet.new(Map.keys(child_to_parents))
    root_ids = MapSet.difference(all_ids, children_ids)

    # Primary roots: roots whose partners are ALL also roots (not children).
    # Married-in spouses (roots partnered with a non-root) get their generation
    # through BFS partner edges instead of being seeded at 0.
    primary_root_ids =
      Enum.filter(root_ids, fn id ->
        partners = Map.get(partner_map, id, [])

        partners == [] or
          Enum.any?(partners, fn pid -> MapSet.member?(root_ids, pid) end)
      end)

    # BFS from primary root nodes
    initial_queue = Enum.map(primary_root_ids, fn id -> {id, 0} end)
    bfs_generations(initial_queue, %{}, parent_to_children, partner_map, all_ids)
  end

  defp bfs_generations([], generations, _parent_to_children, _partner_map, _all_ids) do
    generations
  end

  defp bfs_generations(
         [{person_id, gen} | rest],
         generations,
         parent_to_children,
         partner_map,
         all_ids
       ) do
    if Map.has_key?(generations, person_id) do
      bfs_generations(rest, generations, parent_to_children, partner_map, all_ids)
    else
      generations = Map.put(generations, person_id, gen)

      # Enqueue partners at the same generation
      partner_entries =
        partner_map
        |> Map.get(person_id, [])
        |> Enum.filter(&MapSet.member?(all_ids, &1))
        |> Enum.reject(&Map.has_key?(generations, &1))
        |> Enum.map(fn partner_id -> {partner_id, gen} end)

      # Enqueue children at gen + 1
      child_entries =
        parent_to_children
        |> Map.get(person_id, [])
        |> Enum.filter(&MapSet.member?(all_ids, &1))
        |> Enum.reject(&Map.has_key?(generations, &1))
        |> Enum.map(fn child_id -> {child_id, gen + 1} end)

      new_queue = rest ++ partner_entries ++ child_entries

      bfs_generations(new_queue, generations, parent_to_children, partner_map, all_ids)
    end
  end
end
