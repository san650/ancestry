defmodule Ancestry.People.PersonGraph do
  @moduledoc """
  Builds a person-centered DAG (Directed Acyclic Graph) with N generations
  of ancestors above and N generations of descendants below a focus person.

  Produces a flat list of `GraphNode` structs (each with `col`, `row` grid
  coordinates) and a flat list of `GraphEdge` structs, suitable for direct
  rendering in a CSS Grid.

  ## Algorithm phases

  1. **Traverse & assign generations** — walk up through parent edges,
     down through child edges, applying depth limits and duplication rules.
  2. **Group into family units** — cluster people by generation into
     sibling groups with their partners.
  3. **Order family units** — ensure parent ordering determines child ordering.
  4. **Calculate grid dimensions** — find MAX_WIDTH, pad narrower generations.
  5. **Assign column positions** — starting from widest generation, center
     narrower ones.
  """

  alias Ancestry.People.FamilyGraph
  alias Ancestry.People.GraphEdge
  alias Ancestry.People.GraphNode
  alias Ancestry.People.Person

  @default_opts [ancestors: 2, descendants: 1, other: 0]

  # NOTE: :ancestors, :center, :descendants, :generations are legacy fields
  # kept temporarily for backward compatibility with existing templates.
  # They will be removed when the rendering components are rewritten.
  defstruct [
    :focus_person,
    :family_id,
    :ancestors,
    :center,
    :descendants,
    :generations,
    nodes: [],
    edges: [],
    grid_cols: 0,
    grid_rows: 0
  ]

  @doc """
  Builds a person-centered DAG. Accepts a family_id (builds graph internally)
  or a pre-built %FamilyGraph{} (zero queries). Optionally accepts opts:

    - `ancestors:` — how many generations upward to show (default 2)
    - `descendants:` — how many generations downward to show (default 1)
    - `other:` — accepted but currently unused (default 0)
  """
  def build(focus_person, graph_or_id), do: build(focus_person, graph_or_id, [])

  def build(%Person{} = focus_person, family_id, opts) when is_integer(family_id) do
    build(focus_person, FamilyGraph.for_family(family_id), opts)
  end

  def build(%Person{} = focus_person, %FamilyGraph{} = graph, opts) do
    opts = Keyword.merge(@default_opts, opts)
    max_ancestors = opts[:ancestors]
    max_descendants = opts[:descendants]

    # Phase 1: Traverse & assign generations (new flat DAG)
    state = %{
      visited: %{focus_person.id => 0},
      entries: %{0 => []},
      edges: [],
      focus_id: focus_person.id
    }

    state = add_entry(state, focus_person, 0, false, false, false)

    # Walk ancestors upward
    state = traverse_ancestors(focus_person.id, 1, max_ancestors, graph, state)

    # Walk descendants downward (from focus)
    state = traverse_descendants(focus_person, 0, max_descendants, graph, state)

    # Phase 2-5: Layout
    {nodes, grid_cols, grid_rows} = layout_grid(state, focus_person.id)

    # Legacy tree data (for backward compatibility with existing templates)
    legacy = build_legacy(focus_person, graph, max_ancestors, max_descendants)

    %__MODULE__{
      focus_person: focus_person,
      family_id: graph.family_id,
      nodes: nodes,
      edges: state.edges,
      grid_cols: grid_cols,
      grid_rows: grid_rows,
      ancestors: legacy.ancestors,
      center: legacy.center,
      generations: legacy.generations
    }
  end

  # ── Phase 1: Traversal ──────────────────────────────────────────────

  defp traverse_ancestors(_person_id, generation, max_ancestors, _graph, state)
       when generation > max_ancestors do
    state
  end

  defp traverse_ancestors(person_id, generation, max_ancestors, graph, state) do
    parents = FamilyGraph.parents(graph, person_id)

    # Sort by depth at generation 1 to put deeper lineage first (person_a)
    parents =
      if generation == 1 do
        sort_by_depth(parents, graph)
      else
        parents
      end

    case parents do
      [] ->
        state

      _ ->
        {person_a_raw, person_b_raw} =
          case parents do
            [{p, _}] -> {p, nil}
            [{p1, _}, {p2, _} | _] -> {p1, p2}
          end

        # Check visited, add entries
        {person_a_dup, state} =
          check_and_add_ancestor(person_a_raw, generation, graph, max_ancestors, state)

        {person_b_dup, state} =
          if person_b_raw do
            check_and_add_ancestor(person_b_raw, generation, graph, max_ancestors, state)
          else
            {nil, state}
          end

        # Add parent->child edges
        state = add_parent_child_edge(state, person_a_raw.id, person_id, person_a_dup)

        state =
          if person_b_raw do
            add_parent_child_edge(state, person_b_raw.id, person_id, person_b_dup)
          else
            state
          end

        # Add couple edge between parents if both exist
        state =
          if person_b_raw do
            rel = FamilyGraph.partner_relationship(graph, person_a_raw.id, person_b_raw.id)

            add_couple_edge(
              state,
              person_a_raw.id,
              person_b_raw.id,
              rel,
              person_a_dup,
              person_b_dup
            )
          else
            state
          end

        # Recurse upward only for non-duplicated parents
        state =
          if not person_a_dup do
            traverse_ancestors(person_a_raw.id, generation + 1, max_ancestors, graph, state)
          else
            state
          end

        state =
          if person_b_raw && not person_b_dup do
            traverse_ancestors(person_b_raw.id, generation + 1, max_ancestors, graph, state)
          else
            state
          end

        state
    end
  end

  defp check_and_add_ancestor(person, generation, graph, max_ancestors, state) do
    if Map.has_key?(state.visited, person.id) do
      # Already visited — duplicated
      has_more_up = FamilyGraph.parents(graph, person.id) != []
      state = add_entry(state, person, generation, true, has_more_up, false)
      {true, state}
    else
      has_more_up =
        generation >= max_ancestors and FamilyGraph.parents(graph, person.id) != []

      state = %{state | visited: Map.put(state.visited, person.id, generation)}
      state = add_entry(state, person, generation, false, has_more_up, false)
      {false, state}
    end
  end

  defp traverse_descendants(person, depth, max_descendants, graph, state) do
    if depth >= max_descendants do
      state
    else
      person_gen = -depth
      child_gen = -(depth + 1)
      at_limit = depth + 1 >= max_descendants

      # Get all partners and children
      active_partners = FamilyGraph.active_partners(graph, person.id)
      ex_partners = FamilyGraph.former_partners(graph, person.id)

      # Sort active partners: latest marriage year first
      sorted_active =
        Enum.sort_by(
          active_partners,
          fn {p, rel} ->
            year = if rel.metadata, do: Map.get(rel.metadata, :marriage_year), else: nil
            {year || 0, p.id}
          end,
          :desc
        )

      # Main partner is latest active; rest are previous
      {main_partner, previous_partners} =
        case sorted_active do
          [{p, _rel} | rest] -> {p, rest}
          [] -> {nil, []}
        end

      # Process main partner (at same gen as the person)
      state =
        if main_partner do
          state = ensure_partner_entry(state, main_partner, person_gen, at_limit, graph)
          rel = FamilyGraph.partner_relationship(graph, person.id, main_partner.id)
          add_couple_edge(state, person.id, main_partner.id, rel, false, false)
        else
          state
        end

      # Process children with main partner
      state =
        if main_partner do
          children = FamilyGraph.children_of_pair(graph, person.id, main_partner.id)
          process_children(state, children, child_gen, at_limit, depth, max_descendants, graph)
        else
          state
        end

      # Process previous partners and their children
      state =
        Enum.reduce(previous_partners, state, fn {prev, _rel}, acc ->
          acc = ensure_partner_entry(acc, prev, person_gen, at_limit, graph)
          rel = FamilyGraph.partner_relationship(graph, person.id, prev.id)
          acc = add_couple_edge(acc, person.id, prev.id, rel, false, false)
          children = FamilyGraph.children_of_pair(graph, person.id, prev.id)
          process_children(acc, children, child_gen, at_limit, depth, max_descendants, graph)
        end)

      # Process ex-partners and their children
      state =
        Enum.reduce(ex_partners, state, fn {ex, _rel}, acc ->
          acc = ensure_partner_entry(acc, ex, person_gen, at_limit, graph)
          rel = FamilyGraph.partner_relationship(graph, person.id, ex.id)
          acc = add_couple_edge(acc, person.id, ex.id, rel, false, false)
          children = FamilyGraph.children_of_pair(graph, person.id, ex.id)
          process_children(acc, children, child_gen, at_limit, depth, max_descendants, graph)
        end)

      # Solo children
      solo_children = FamilyGraph.solo_children(graph, person.id)
      process_children(state, solo_children, child_gen, at_limit, depth, max_descendants, graph)
    end
  end

  defp ensure_partner_entry(state, partner, person_gen, at_limit, graph) do
    if Map.has_key?(state.visited, partner.id) do
      state
    else
      # Partner is placed at the same generation as the person they partner with
      has_more_down = at_limit and FamilyGraph.has_children?(graph, partner.id)

      state = %{state | visited: Map.put(state.visited, partner.id, person_gen)}
      add_entry(state, partner, person_gen, false, false, has_more_down)
    end
  end

  defp process_children(state, children, child_gen, at_limit, depth, max_descendants, graph) do
    Enum.reduce(children, state, fn child, acc ->
      if Map.has_key?(acc.visited, child.id) do
        # Duplicated child
        acc = add_entry(acc, child, child_gen, true, false, false)
        # Still add parent->child edges
        add_child_parent_edges(acc, child, graph)
      else
        has_more_down = at_limit and FamilyGraph.has_children?(graph, child.id)
        acc = %{acc | visited: Map.put(acc.visited, child.id, child_gen)}
        acc = add_entry(acc, child, child_gen, false, false, has_more_down)

        # Add parent->child edges
        acc = add_child_parent_edges(acc, child, graph)

        if at_limit do
          # At limit: add partner info but don't recurse further
          add_at_limit_partners(acc, child, child_gen, graph)
        else
          traverse_descendants(child, depth + 1, max_descendants, graph, acc)
        end
      end
    end)
  end

  defp add_child_parent_edges(state, child, graph) do
    parents = FamilyGraph.parents(graph, child.id)

    Enum.reduce(parents, state, fn {parent, _rel}, acc ->
      if Map.has_key?(acc.visited, parent.id) do
        add_parent_child_edge(acc, parent.id, child.id, false)
      else
        acc
      end
    end)
  end

  defp add_at_limit_partners(state, child, child_gen, graph) do
    all_partners = FamilyGraph.all_partners(graph, child.id)

    sorted_partners =
      Enum.sort_by(
        all_partners,
        fn {p, rel} ->
          year = if rel.metadata, do: Map.get(rel.metadata, :marriage_year), else: nil
          {year || 0, p.id}
        end,
        :desc
      )

    Enum.reduce(sorted_partners, state, fn {partner, _rel}, acc ->
      if Map.has_key?(acc.visited, partner.id) do
        # Partner already in graph — add couple edge but mark as dup in entry
        rel = FamilyGraph.partner_relationship(graph, child.id, partner.id)
        acc = add_entry(acc, partner, child_gen, true, false, false)
        add_couple_edge(acc, child.id, partner.id, rel, false, true)
      else
        acc = %{acc | visited: Map.put(acc.visited, partner.id, child_gen)}
        has_more_down = FamilyGraph.has_children?(graph, partner.id)
        acc = add_entry(acc, partner, child_gen, false, false, has_more_down)
        rel = FamilyGraph.partner_relationship(graph, child.id, partner.id)
        add_couple_edge(acc, child.id, partner.id, rel, false, false)
      end
    end)
  end

  # ── Entry and edge helpers ──────────────────────────────────────────

  defp add_entry(state, person, gen, duplicated, has_more_up, has_more_down) do
    entry = %{
      person: person,
      gen: gen,
      duplicated: duplicated,
      has_more_up: has_more_up,
      has_more_down: has_more_down,
      focus: person.id == state.focus_id
    }

    entries = Map.update(state.entries, gen, [entry], &(&1 ++ [entry]))
    %{state | entries: entries}
  end

  defp add_parent_child_edge(state, parent_id, child_id, parent_dup) do
    from_id = if parent_dup, do: "person-#{parent_id}-dup", else: "person-#{parent_id}"

    edge = %GraphEdge{
      type: :parent_child,
      relationship_kind: "parent",
      from_id: from_id,
      to_id: "person-#{child_id}"
    }

    %{state | edges: state.edges ++ [edge]}
  end

  defp add_couple_edge(state, person_a_id, person_b_id, rel, a_dup, b_dup) do
    rel_kind = if rel, do: rel.type, else: "married"

    edge_type =
      case rel_kind do
        t when t in ~w(divorced separated) -> :previous_partner
        _ -> :current_partner
      end

    from_id = if a_dup, do: "person-#{person_a_id}-dup", else: "person-#{person_a_id}"
    to_id = if b_dup, do: "person-#{person_b_id}-dup", else: "person-#{person_b_id}"

    edge = %GraphEdge{
      type: edge_type,
      relationship_kind: rel_kind,
      from_id: from_id,
      to_id: to_id
    }

    %{state | edges: state.edges ++ [edge]}
  end

  # ── Phases 2-5: Grid Layout ─────────────────────────────────────────

  defp layout_grid(state, focus_id) do
    entries = state.entries

    if map_size(entries) == 0 do
      {[], 0, 0}
    else
      # Normalize generations: highest gen (ancestors) = row 0
      all_gens = Map.keys(entries)
      max_gen = Enum.max(all_gens)
      min_gen = Enum.min(all_gens)
      grid_rows = max_gen - min_gen + 1

      # Convert entries to rows (row 0 = highest ancestor gen)
      rows =
        for gen <- max_gen..min_gen//-1 do
          people = Map.get(entries, gen, [])
          {max_gen - gen, people}
        end

      # Phase 2-3: Order entries within each row
      # For now, maintain insertion order (which follows traversal order)
      # This gives correct family-unit grouping from the traversal

      # Phase 4: Calculate widths
      row_widths =
        Enum.map(rows, fn {_row_idx, people} ->
          length(people)
        end)

      max_width = Enum.max(row_widths, fn -> 1 end)
      max_width = max(max_width, 1)

      # Phase 5: Assign column positions
      # Center each row within max_width
      nodes =
        Enum.flat_map(rows, fn {row_idx, people} ->
          count = length(people)
          # Calculate starting column to center this row
          start_col = div(max_width - count, 2)

          # Create person nodes
          person_nodes =
            people
            |> Enum.with_index()
            |> Enum.map(fn {entry, idx} ->
              col = start_col + idx
              node_id = make_node_id(entry.person.id, entry.duplicated, focus_id, entry)

              %GraphNode{
                id: node_id,
                type: :person,
                col: col,
                row: row_idx,
                person: entry.person,
                focus: entry.focus,
                duplicated: entry.duplicated,
                has_more_up: entry.has_more_up,
                has_more_down: entry.has_more_down
              }
            end)

          # Add separator nodes for remaining columns
          used_cols = MapSet.new(person_nodes, & &1.col)

          separator_nodes =
            for col <- 0..(max_width - 1),
                not MapSet.member?(used_cols, col) do
              %GraphNode{
                id: "sep-#{row_idx}-#{col}",
                type: :separator,
                col: col,
                row: row_idx
              }
            end

          person_nodes ++ separator_nodes
        end)

      {nodes, max_width, grid_rows}
    end
  end

  defp make_node_id(person_id, duplicated, _focus_id, _entry) do
    if duplicated do
      "person-#{person_id}-dup"
    else
      "person-#{person_id}"
    end
  end

  # ── Depth sorting helpers ───────────────────────────────────────────

  defp sort_by_depth(parents, graph) do
    Enum.sort_by(parents, fn {p, _rel} -> max_ancestor_depth(p.id, graph) end, :desc)
  end

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

  # ── Legacy tree builder (backward compat with existing templates) ───
  # TODO: Remove when rendering components are rewritten (Tasks 5-8).

  defp build_legacy(focus_person, graph, max_ancestors, max_descendants) do
    visited = %{focus_person.id => 0}

    {ancestor_tree, visited} =
      legacy_ancestor_tree(focus_person.id, 1, max_ancestors, graph, visited)

    {center, visited} =
      legacy_family_unit(focus_person, 0, max_descendants, graph, visited)

    max_gen = visited |> Map.values() |> Enum.max()
    generations = Map.new(visited, fn {person_id, gen} -> {person_id, max_gen - gen} end)

    %{ancestors: ancestor_tree, center: center, generations: generations}
  end

  defp legacy_family_unit(person, depth, max_descendants, graph, visited) do
    partners = FamilyGraph.active_partners(graph, person.id)
    ex_partners = FamilyGraph.former_partners(graph, person.id)

    sorted_partners =
      Enum.sort_by(
        partners,
        fn {p, rel} ->
          year = if rel.metadata, do: Map.get(rel.metadata, :marriage_year), else: nil
          {year || 0, p.id}
        end,
        :desc
      )

    {partner, previous} =
      case sorted_partners do
        [{p, _rel} | rest] -> {p, rest}
        [] -> {nil, []}
      end

    {partner_children, visited} =
      if partner do
        FamilyGraph.children_of_pair(graph, person.id, partner.id)
        |> legacy_child_units(depth, max_descendants, graph, visited)
      else
        {[], visited}
      end

    {previous_partner_groups, visited} =
      Enum.reduce(previous, {[], visited}, fn {prev, _rel}, {groups, vis} ->
        {children, vis} =
          FamilyGraph.children_of_pair(graph, person.id, prev.id)
          |> legacy_child_units(depth, max_descendants, graph, vis)

        {groups ++ [%{person: prev, children: children}], vis}
      end)

    {ex_partner_groups, visited} =
      Enum.reduce(ex_partners, {[], visited}, fn {ex, _rel}, {groups, vis} ->
        {children, vis} =
          FamilyGraph.children_of_pair(graph, person.id, ex.id)
          |> legacy_child_units(depth, max_descendants, graph, vis)

        {groups ++ [%{person: ex, children: children}], vis}
      end)

    {solo_children, visited} =
      FamilyGraph.solo_children(graph, person.id)
      |> legacy_child_units(depth, max_descendants, graph, visited)

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

  defp legacy_child_units(children, depth, max_descendants, graph, visited) do
    if depth >= max_descendants do
      {[], visited}
    else
      at_limit = depth + 1 >= max_descendants

      {units, vis, _seen} =
        Enum.reduce(children, {[], visited, MapSet.new()}, fn child,
                                                              {units, vis, seen_partners} ->
          if Map.has_key?(vis, child.id) do
            {units ++ [%{person: child, duplicated: true, has_more: false, children: nil}], vis,
             seen_partners}
          else
            vis = Map.put(vis, child.id, -(depth + 1))

            if at_limit do
              has_more = FamilyGraph.has_children?(graph, child.id)
              all_partners = FamilyGraph.all_partners(graph, child.id)

              sorted_p =
                Enum.sort_by(
                  all_partners,
                  fn {p, rel} ->
                    year =
                      if rel.metadata, do: Map.get(rel.metadata, :marriage_year), else: nil

                    {year || 0, p.id}
                  end,
                  :desc
                )

              {lp, lprev} =
                case sorted_p do
                  [{p, _rel} | rest] -> {p, rest}
                  [] -> {nil, []}
                end

              partner_id = lp && lp.id
              partner_duplicated = partner_id != nil and MapSet.member?(seen_partners, partner_id)

              {previous_partners, seen_partners} =
                Enum.reduce(lprev, {[], seen_partners}, fn {p, _rel}, {pps, sp} ->
                  dup = MapSet.member?(sp, p.id)

                  {pps ++ [%{person: p, children: nil, duplicated: dup}], MapSet.put(sp, p.id)}
                end)

              seen_partners =
                if partner_id, do: MapSet.put(seen_partners, partner_id), else: seen_partners

              {units ++
                 [
                   %{
                     person: child,
                     partner: lp,
                     partner_duplicated: partner_duplicated,
                     previous_partners: previous_partners,
                     has_more: has_more,
                     children: nil
                   }
                 ], vis, seen_partners}
            else
              {unit, vis} =
                legacy_family_unit(child, depth + 1, max_descendants, graph, vis)

              has_children =
                unit.partner_children != [] or unit.solo_children != [] or
                  unit.ex_partners != []

              unit = Map.put(unit, :has_more, false) |> Map.put(:has_children, has_children)
              {units ++ [unit], vis, seen_partners}
            end
          end
        end)

      {units, vis}
    end
  end

  defp legacy_ancestor_tree(_person_id, generation, max_ancestors, _graph, visited)
       when generation > max_ancestors do
    {nil, visited}
  end

  defp legacy_ancestor_tree(person_id, generation, max_ancestors, graph, visited) do
    parents = FamilyGraph.parents(graph, person_id)

    parents =
      if generation == 1 do
        sort_by_depth(parents, graph)
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

        {person_a_entry, visited} = legacy_check_mark(person_a_raw, generation, visited)

        {person_b_entry, visited} =
          if person_b_raw,
            do: legacy_check_mark(person_b_raw, generation, visited),
            else: {nil, visited}

        {parent_trees, visited} =
          [person_a_entry, person_b_entry]
          |> Enum.reject(&is_nil/1)
          |> Enum.reject(& &1.duplicated)
          |> Enum.reduce({[], visited}, fn entry, {trees, vis} ->
            case legacy_ancestor_tree(
                   entry.person.id,
                   generation + 1,
                   max_ancestors,
                   graph,
                   vis
                 ) do
              {nil, vis} -> {trees, vis}
              {tree, vis} -> {trees ++ [%{tree: tree, for_person_id: entry.person.id}], vis}
            end
          end)

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

        {node, visited}
    end
  end

  defp legacy_check_mark(person, generation, visited) do
    if Map.has_key?(visited, person.id) do
      {%{person: person, duplicated: true}, visited}
    else
      {%{person: person, duplicated: false}, Map.put(visited, person.id, generation)}
    end
  end
end
