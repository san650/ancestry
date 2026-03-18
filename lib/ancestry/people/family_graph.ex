defmodule Ancestry.People.FamilyGraph do
  @moduledoc """
  Builds a family graph data structure from people and relationships.

  Takes a list of `%Person{}` structs and `%Relationship{}` structs, builds an
  Erlang `:digraph` for connected component detection, computes generations via
  BFS from root nodes, and returns a flat `%FamilyGraph{}` struct.
  """

  alias __MODULE__.Cell
  alias __MODULE__.ChildEdge
  alias __MODULE__.Grid
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

  @doc """
  Convert a FamilyGraph into a 2D grid of cells for rendering.

  Returns a `%Grid{}` with person, union, and connector cells placed
  at `{row, col}` positions.
  """
  def to_grid(%__MODULE__{components: [], unconnected: []}) do
    %Grid{rows: 0, cols: 0, cells: %{}}
  end

  def to_grid(%__MODULE__{} = graph) do
    union_by_id = Map.new(graph.unions, fn u -> {u.id, u} end)

    # Build person_id -> generation lookup from graph nodes
    person_gen = Map.new(graph.nodes, fn {pid, node} -> {pid, node.generation} end)

    {all_cells, total_rows, max_cols} =
      graph.components
      |> Enum.reduce({%{}, 0, 0}, fn component_ids, {cells, row_offset, max_col} ->
        row_offset = if map_size(cells) > 0, do: row_offset + 1, else: row_offset

        {comp_cells, comp_rows, comp_cols} =
          layout_component(component_ids, graph, union_by_id, person_gen)

        shifted_cells =
          Map.new(comp_cells, fn {{r, c}, cell} -> {{r + row_offset, c}, cell} end)

        merged = Map.merge(cells, shifted_cells)
        {merged, row_offset + comp_rows, max(max_col, comp_cols)}
      end)

    %Grid{rows: total_rows, cols: max_cols, cells: all_cells}
  end

  defp layout_component(person_ids, graph, union_by_id, person_gen) do
    person_id_set = MapSet.new(person_ids)

    gen_groups =
      person_ids
      |> Enum.group_by(fn pid -> graph.nodes[pid].generation end)
      |> Enum.sort_by(fn {gen, _} -> gen end)

    component_unions =
      Enum.filter(graph.unions, fn u ->
        MapSet.member?(person_id_set, u.person_a_id) and
          MapSet.member?(person_id_set, u.person_b_id)
      end)

    component_child_edges =
      Enum.filter(graph.child_edges, fn edge ->
        MapSet.member?(person_id_set, edge.to)
      end)

    {node_cells, col_map, row_count, gen_to_row} =
      layout_generation_rows(gen_groups, component_unions)

    connector_cells =
      build_connectors(gen_to_row, col_map, component_child_edges, union_by_id, person_gen)

    all_cells = Map.merge(node_cells, connector_cells)

    max_col =
      if map_size(all_cells) > 0 do
        all_cells |> Map.keys() |> Enum.map(fn {_r, c} -> c end) |> Enum.max() |> Kernel.+(1)
      else
        0
      end

    {all_cells, row_count, max_col}
  end

  defp layout_generation_rows(gen_groups, unions) do
    gen_groups
    |> Enum.reduce({%{}, %{}, 0, %{}}, fn {gen, pids}, {cells, col_map, current_row, gen_rows} ->
      gen_set = MapSet.new(pids)

      gen_unions =
        Enum.filter(unions, fn u ->
          MapSet.member?(gen_set, u.person_a_id) and MapSet.member?(gen_set, u.person_b_id)
        end)

      gen_union_adj =
        Enum.reduce(gen_unions, %{}, fn u, acc ->
          acc
          |> Map.update(u.person_a_id, [{u, u.person_b_id}], &[{u, u.person_b_id} | &1])
          |> Map.update(u.person_b_id, [{u, u.person_a_id}], &[{u, u.person_a_id} | &1])
        end)

      chains = build_chains(pids, gen_union_adj)

      {gen_cells, new_col_map, _next_col} =
        place_chains(chains, current_row, col_map)

      next_row = current_row + 2

      {
        Map.merge(cells, gen_cells),
        new_col_map,
        next_row,
        Map.put(gen_rows, gen, current_row)
      }
    end)
    |> then(fn {cells, col_map, total_row, gen_rows} ->
      adjusted_rows = if total_row > 0, do: total_row - 1, else: 0
      {cells, col_map, adjusted_rows, gen_rows}
    end)
  end

  defp build_chains(person_ids, gen_union_adj) do
    {chains, _visited} =
      Enum.reduce(person_ids, {[], MapSet.new()}, fn pid, {chains_acc, visited_acc} ->
        if MapSet.member?(visited_acc, pid) do
          {chains_acc, visited_acc}
        else
          {chain, new_visited} = walk_chain(pid, gen_union_adj, visited_acc)
          {[chain | chains_acc], new_visited}
        end
      end)

    Enum.reverse(chains)
  end

  defp walk_chain(start_pid, gen_union_adj, visited) do
    endpoint = find_chain_endpoint(start_pid, gen_union_adj, visited)
    do_walk_chain(endpoint, gen_union_adj, visited, [])
  end

  defp find_chain_endpoint(pid, gen_union_adj, visited) do
    find_endpoint_walk(pid, gen_union_adj, visited, MapSet.new([pid]))
  end

  defp find_endpoint_walk(pid, gen_union_adj, visited, seen) do
    neighbors =
      gen_union_adj
      |> Map.get(pid, [])
      |> Enum.reject(fn {_u, other} ->
        MapSet.member?(visited, other) or MapSet.member?(seen, other)
      end)

    case neighbors do
      [] ->
        pid

      [{_u, next_pid} | _] ->
        find_endpoint_walk(next_pid, gen_union_adj, visited, MapSet.put(seen, next_pid))
    end
  end

  defp do_walk_chain(pid, gen_union_adj, visited, chain) do
    visited = MapSet.put(visited, pid)
    chain = chain ++ [{:person, pid}]

    neighbors =
      gen_union_adj
      |> Map.get(pid, [])
      |> Enum.reject(fn {_u, other} -> MapSet.member?(visited, other) end)

    case neighbors do
      [] ->
        {chain, visited}

      [{union, next_pid} | _] ->
        chain = chain ++ [{:union, union.id}]
        do_walk_chain(next_pid, gen_union_adj, visited, chain)
    end
  end

  defp place_chains(chains, row, col_map) do
    start_col =
      if map_size(col_map) > 0 do
        col_map |> Map.values() |> Enum.max() |> Kernel.+(2)
      else
        0
      end

    chains
    |> Enum.reduce({%{}, col_map, start_col}, fn chain, {cells, cmap, col} ->
      col = if col > start_col, do: col + 1, else: col

      Enum.reduce(chain, {cells, cmap, col}, fn elem, {c, cm, cur_col} ->
        cell =
          case elem do
            {:person, pid} -> %Cell{type: :person, data: %{person_id: pid}}
            {:union, uid} -> %Cell{type: :union, data: %{union_id: uid}}
          end

        {
          Map.put(c, {row, cur_col}, cell),
          Map.put(cm, elem, cur_col),
          cur_col + 1
        }
      end)
    end)
  end

  defp build_connectors(gen_to_row, col_map, child_edges, union_by_id, person_gen) do
    Enum.reduce(child_edges, %{}, fn edge, cells ->
      source_col = find_source_col(edge.from, col_map)
      child_col = Map.get(col_map, {:person, edge.to})
      source_row = find_source_row(edge.from, gen_to_row, union_by_id, person_gen)

      cond do
        is_nil(source_col) or is_nil(child_col) or is_nil(source_row) ->
          cells

        source_col == child_col ->
          connector_row = source_row + 1
          Map.put(cells, {connector_row, source_col}, %Cell{type: :vertical, data: %{}})

        true ->
          connector_row = source_row + 1
          place_connector_path(cells, connector_row, source_col, child_col)
      end
    end)
  end

  defp find_source_col(from, col_map) do
    Map.get(col_map, from)
  end

  defp find_source_row({:union, uid}, gen_to_row, union_by_id, person_gen) do
    case Map.get(union_by_id, uid) do
      nil ->
        nil

      union ->
        gen = Map.get(person_gen, union.person_a_id)
        if gen, do: Map.get(gen_to_row, gen), else: nil
    end
  end

  defp find_source_row({:person, pid}, gen_to_row, _union_by_id, person_gen) do
    gen = Map.get(person_gen, pid)
    if gen, do: Map.get(gen_to_row, gen), else: nil
  end

  defp place_connector_path(cells, row, source_col, child_col) do
    {left, right} = {min(source_col, child_col), max(source_col, child_col)}

    cells = Map.put_new(cells, {row, source_col}, %Cell{type: :t_down, data: %{}})

    corner_type = if child_col > source_col, do: :top_right, else: :top_left
    cells = Map.put_new(cells, {row, child_col}, %Cell{type: corner_type, data: %{}})

    Enum.reduce((left + 1)..(right - 1)//1, cells, fn c, acc ->
      if c != source_col and c != child_col do
        Map.put_new(acc, {row, c}, %Cell{type: :horizontal, data: %{}})
      else
        acc
      end
    end)
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
