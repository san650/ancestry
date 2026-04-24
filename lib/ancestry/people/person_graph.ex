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

  @default_opts [ancestors: 2, descendants: 2, other: 1]

  defstruct [
    :focus_person,
    :family_id,
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
    - `other:` — how many ancestor levels to expand laterally (siblings, cousins, etc.) (default 1)
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
      focus_id: focus_person.id,
      graph: graph
    }

    state = add_entry(state, focus_person, 0, false, false, false)

    # Walk ancestors upward
    state = traverse_ancestors(focus_person.id, 1, max_ancestors, graph, state)

    # Fix cross-generation inconsistencies (e.g., Type 4: uncle marries niece)
    state = fix_cross_gen_ancestors(state, graph)

    # Walk descendants downward (from focus)
    state = traverse_descendants(focus_person, 0, max_descendants, graph, state)

    # Walk lateral relatives (siblings, cousins, etc.)
    max_other = min(opts[:other], max_ancestors)
    state = traverse_laterals(state, max_other, max_descendants, graph)

    # Phase 2-5: Layout
    {nodes, grid_cols, grid_rows} = layout_grid(state, focus_person.id)

    %__MODULE__{
      focus_person: focus_person,
      family_id: graph.family_id,
      nodes: nodes,
      edges: state.edges,
      grid_cols: grid_cols,
      grid_rows: grid_rows
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
          cond do
            is_nil(person_b_raw) ->
              {nil, state}

            person_b_raw.id == person_a_raw.id ->
              # Same person as both parents (bad data) — always dup the second one
              has_more_up = FamilyGraph.parents(graph, person_b_raw.id) != []
              state = add_entry(state, person_b_raw, generation, true, has_more_up, false)
              {true, state}

            true ->
              check_and_add_ancestor(person_b_raw, generation, graph, max_ancestors, state)
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
    case Map.fetch(state.visited, person.id) do
      {:ok, existing_gen} when existing_gen == generation ->
        # Rule 1: Same generation + compatible position → REUSE.
        # Don't create a dup entry. The existing node serves the new role.
        # Edges will connect to the existing "person-{id}" node.
        {false, state}

      {:ok, _existing_gen} ->
        # Rule 3: Different generation → always DUP.
        has_more_up = FamilyGraph.parents(graph, person.id) != []
        state = add_entry(state, person, generation, true, has_more_up, false)
        {true, state}

      :error ->
        # First encounter — place normally.
        has_more_up =
          generation >= max_ancestors and FamilyGraph.parents(graph, person.id) != []

        state = %{state | visited: Map.put(state.visited, person.id, generation)}
        state = add_entry(state, person, generation, false, has_more_up, false)
        {false, state}
    end
  end

  # ── Cross-generation fix (Type 4: uncle marries niece) ──────────────
  #
  # After ancestor traversal, detect persons whose parents are ALL at a
  # generation higher than expected (parent_gen > person_gen + 1). This
  # means the person was placed too low (e.g., Uncle at gen 1 when his
  # sibling Brother is at gen 2). Fix by:
  #   1. Moving the person from their current gen to parent_gen - 1
  #   2. Creating a dup stub at the original gen (for the couple with their partner)
  #   3. Updating edges to point to the correct node IDs
  #   4. Removing dup entries for parents that were created due to the gen mismatch

  defp fix_cross_gen_ancestors(state, graph) do
    # Find persons who need gen correction: their parents are all at
    # a gen that is >= 2 higher than the person's gen (not adjacent).
    persons_to_fix =
      state.visited
      |> Enum.filter(fn {person_id, person_gen} ->
        # Only check ancestor-side persons (gen > 0) that aren't the focus
        person_gen > 0 and person_id != state.focus_id and
          needs_gen_correction?(person_id, person_gen, state, graph)
      end)

    Enum.reduce(persons_to_fix, state, fn {person_id, old_gen}, acc ->
      relocate_person_to_correct_gen(acc, person_id, old_gen, graph)
    end)
  end

  defp needs_gen_correction?(person_id, person_gen, state, graph) do
    parents = FamilyGraph.parents(graph, person_id)

    case parents do
      [] ->
        false

      parents ->
        # Check if ALL parents are at a gen that's > person_gen + 1
        # (meaning there's a gap — person should be at parent_gen - 1)
        Enum.all?(parents, fn {parent, _rel} ->
          case Map.fetch(state.visited, parent.id) do
            {:ok, parent_gen} -> parent_gen > person_gen + 1
            :error -> false
          end
        end)
    end
  end

  defp relocate_person_to_correct_gen(state, person_id, old_gen, graph) do
    parents = FamilyGraph.parents(graph, person_id)

    # Determine correct gen from parents
    parent_gens =
      parents
      |> Enum.map(fn {p, _} -> Map.get(state.visited, p.id) end)
      |> Enum.reject(&is_nil/1)

    new_gen =
      case parent_gens do
        [] -> old_gen
        gens -> Enum.min(gens) - 1
      end

    if new_gen == old_gen do
      state
    else
      person =
        state.entries
        |> Map.get(old_gen, [])
        |> Enum.find(fn e -> e.person.id == person_id and not e.duplicated end)

      if is_nil(person) do
        state
      else
        # 1. Remove dup entries for parents that were created at old_gen + 1
        #    due to the gen mismatch (they're no longer needed since the
        #    person is moving to the correct gen where parents are adjacent)
        parent_ids = MapSet.new(parents, fn {p, _} -> p.id end)

        cleaned_entries =
          state.entries
          |> Enum.map(fn {gen, entries} ->
            cleaned =
              Enum.reject(entries, fn e ->
                e.duplicated and MapSet.member?(parent_ids, e.person.id) and
                  e.gen == old_gen + 1
              end)

            {gen, cleaned}
          end)
          |> Map.new()

        # 2. Remove person from old gen entries
        old_entries = Map.get(cleaned_entries, old_gen, [])

        remaining_old =
          Enum.reject(old_entries, fn e -> e.person.id == person_id and not e.duplicated end)

        # 3. Add dup stub at old gen (for the couple with their partner)
        dup_entry = %{person | gen: old_gen, duplicated: true}

        # 4. Add person at new gen (non-dup)
        new_entry = %{person | gen: new_gen}
        new_gen_entries = Map.get(cleaned_entries, new_gen, []) ++ [new_entry]

        entries =
          cleaned_entries
          |> Map.put(old_gen, remaining_old ++ [dup_entry])
          |> Map.put(new_gen, new_gen_entries)

        # 5. Update visited map
        visited = Map.put(state.visited, person_id, new_gen)

        # 6. Fix edges related to the removed parent dups:
        #    - Parent→child edges from dup parents to this person:
        #      change from_id from "person-X-dup" to "person-X"
        #    - Remove couple edges between dup parents (they no longer exist)
        #    - Remove parent→child edges FROM dup parents to this person
        #      that reference the dup IDs AND came from the dup entries

        # Set of dup parent node IDs that were removed
        dup_parent_node_ids =
          MapSet.new(parents, fn {p, _} -> "person-#{p.id}-dup" end)

        edges =
          state.edges
          |> Enum.reject(fn edge ->
            # Remove couple edges between the dup parents (both ends are dup IDs)
            edge.type in [:current_partner, :previous_partner] and
              MapSet.member?(dup_parent_node_ids, edge.from_id) and
              MapSet.member?(dup_parent_node_ids, edge.to_id)
          end)
          |> Enum.map(fn edge ->
            cond do
              # Parent→child edges TO this person from parents that were dup'd:
              # change from_id from "person-X-dup" to "person-X"
              edge.type == :parent_child and
                edge.to_id == "person-#{person_id}" and
                  MapSet.member?(dup_parent_node_ids, edge.from_id) ->
                from_id =
                  edge.from_id
                  |> String.replace_suffix("-dup", "")

                %{edge | from_id: from_id}

              true ->
                edge
            end
          end)

        # 7. Update couple edges: the couple edge between person and their partner
        #    at old_gen should use the dup ID for this person
        edges =
          Enum.map(edges, fn edge ->
            if edge.type in [:current_partner, :previous_partner] and
                 (edge.from_id == "person-#{person_id}" or
                    edge.to_id == "person-#{person_id}") do
              # Check if the OTHER partner is at old_gen
              other_id =
                if edge.from_id == "person-#{person_id}",
                  do: edge.to_id,
                  else: edge.from_id

              other_person_id = extract_person_id(other_id)
              other_gen = Map.get(visited, other_person_id)

              if other_gen == old_gen do
                # The couple is at old_gen — use dup ID for the relocated person
                if edge.from_id == "person-#{person_id}" do
                  %{edge | from_id: "person-#{person_id}-dup"}
                else
                  %{edge | to_id: "person-#{person_id}-dup"}
                end
              else
                edge
              end
            else
              edge
            end
          end)

        # 8. Update parent→child edges FROM this person: if the child is at
        #    old_gen - 1, the edge should come from the dup
        edges =
          Enum.map(edges, fn edge ->
            if edge.type == :parent_child and edge.from_id == "person-#{person_id}" do
              child_person_id = extract_person_id(edge.to_id)
              child_gen = Map.get(visited, child_person_id)

              if child_gen != nil and child_gen < old_gen do
                %{edge | from_id: "person-#{person_id}-dup"}
              else
                edge
              end
            else
              edge
            end
          end)

        %{state | entries: entries, visited: visited, edges: edges}
      end
    end
  end

  defp extract_person_id(node_id) do
    id_str =
      node_id
      |> String.replace_prefix("person-", "")
      |> String.replace_suffix("-dup", "")

    case Integer.parse(id_str) do
      {id, ""} -> id
      _ -> nil
    end
  end

  defp traverse_laterals(state, 0, _max_descendants, _graph), do: state

  defp traverse_laterals(state, max_other, max_descendants, graph) do
    focus_id = state.focus_id

    # Collect ancestors by generation
    ancestors_by_gen =
      state.visited
      |> Enum.filter(fn {id, gen} -> gen > 0 and id != focus_id end)
      |> Enum.group_by(fn {_id, gen} -> gen end, fn {id, _gen} -> id end)

    # Process from closest ancestors outward (gen 1 first, then gen 2, etc.)
    Enum.reduce(1..max_other, state, fn gen, acc ->
      ancestor_ids = Map.get(ancestors_by_gen, gen, [])

      Enum.reduce(ancestor_ids, acc, fn ancestor_id, acc2 ->
        children = FamilyGraph.children(graph, ancestor_id)
        new_children = Enum.reject(children, &Map.has_key?(acc2.visited, &1.id))
        child_gen = gen - 1

        Enum.reduce(new_children, acc2, fn child, acc3 ->
          depth = -child_gen
          at_limit = depth >= max_descendants

          has_more_down = at_limit and FamilyGraph.has_children?(graph, child.id)
          acc3 = %{acc3 | visited: Map.put(acc3.visited, child.id, child_gen)}
          acc3 = add_entry(acc3, child, child_gen, false, false, has_more_down)
          acc3 = add_child_parent_edges(acc3, child, graph)

          if at_limit do
            add_at_limit_partners(acc3, child, child_gen, graph)
          else
            traverse_descendants(child, depth, max_descendants, graph, acc3)
          end
        end)
      end)
    end)
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

      # Select current partner using priority cascade
      {current_tuple, other_active} = select_current_partner(active_partners)
      main_partner = if current_tuple, do: elem(current_tuple, 0), else: nil
      previous_partners = other_active

      # === Processing order: ex → previous → solo → current partner + children ===
      # Grid lays out entries left-to-right by insertion order, so processing
      # ex-partner children first puts them on the left (leftmost in grid).

      # 1. Process ex-partners and their children (leftmost)
      state =
        Enum.reduce(ex_partners, state, fn {ex, _rel}, acc ->
          acc = ensure_partner_entry(acc, ex, person_gen, at_limit, graph)
          rel = FamilyGraph.partner_relationship(graph, person.id, ex.id)
          acc = add_couple_edge(acc, person.id, ex.id, rel, false, false)
          children = FamilyGraph.children_of_pair(graph, person.id, ex.id)

          process_children(acc, children, child_gen, at_limit, depth, max_descendants, graph)
        end)

      # 2. Process previous (non-current) active partners and their children
      # Force :previous_partner edge type so reorder_partners places them before the person
      state =
        Enum.reduce(previous_partners, state, fn {prev, _rel}, acc ->
          acc = ensure_partner_entry(acc, prev, person_gen, at_limit, graph)
          rel = FamilyGraph.partner_relationship(graph, person.id, prev.id)
          acc = add_couple_edge(acc, person.id, prev.id, rel, false, false, :previous_partner)
          children = FamilyGraph.children_of_pair(graph, person.id, prev.id)

          process_children(acc, children, child_gen, at_limit, depth, max_descendants, graph)
        end)

      # 3. Solo children
      solo_children = FamilyGraph.solo_children(graph, person.id)

      state =
        process_children(state, solo_children, child_gen, at_limit, depth, max_descendants, graph)

      # 4. Process main (current) partner entry + couple edge (rightmost)
      state =
        if main_partner do
          state = ensure_partner_entry(state, main_partner, person_gen, at_limit, graph)
          rel = FamilyGraph.partner_relationship(graph, person.id, main_partner.id)
          add_couple_edge(state, person.id, main_partner.id, rel, false, false)
        else
          state
        end

      # 5. Process children with main partner (rightmost in grid)
      if main_partner do
        children = FamilyGraph.children_of_pair(graph, person.id, main_partner.id)
        process_children(state, children, child_gen, at_limit, depth, max_descendants, graph)
      else
        state
      end
    end
  end

  # Selects the current partner from a list of active partners using a priority cascade:
  # 1. "relationship" type takes priority (currently dating)
  # 2. Among "married" partners: latest marriage_year, or non-deceased if no dates
  # 3. Returns {current_partner_tuple | nil, other_partners_list}
  defp select_current_partner([]), do: {nil, []}

  defp select_current_partner(active_partners) do
    # Rule 1: "relationship" type takes priority
    relationship = Enum.find(active_partners, fn {_p, rel} -> rel.type == "relationship" end)

    if relationship do
      others = Enum.reject(active_partners, fn {p, _} -> p.id == elem(relationship, 0).id end)
      {relationship, others}
    else
      married = Enum.filter(active_partners, fn {_p, rel} -> rel.type == "married" end)

      case married do
        [] ->
          {nil, active_partners}

        [single] ->
          rest = Enum.reject(active_partners, fn {p, _} -> p.id == elem(single, 0).id end)
          {single, rest}

        multiple ->
          # Rule 2a: Pick latest marriage_year
          with_dates =
            Enum.filter(multiple, fn {_p, rel} ->
              rel.metadata && Map.get(rel.metadata, :marriage_year)
            end)

          current =
            if with_dates != [] do
              Enum.max_by(with_dates, fn {_p, rel} -> Map.get(rel.metadata, :marriage_year) end)
            else
              # Rule 2b: No dates → pick non-deceased
              non_deceased = Enum.reject(multiple, fn {p, _} -> p.deceased end)

              case non_deceased do
                [first | _] -> first
                [] -> hd(multiple)
              end
            end

          rest = Enum.reject(active_partners, fn {p, _} -> p.id == elem(current, 0).id end)
          {current, rest}
      end
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

  defp add_couple_edge(
         state,
         person_a_id,
         person_b_id,
         rel,
         a_dup,
         b_dup,
         edge_type_override \\ nil
       ) do
    rel_kind = if rel, do: rel.type, else: "married"

    edge_type =
      edge_type_override ||
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

    # Fix has_more_down indicators: if all children are already in the DAG,
    # the person shouldn't show a "has more descendants" indicator
    entries = fix_has_more_indicators(entries, state)

    # Reorder partners within each generation so that ex/previous partners
    # come before the person and the current partner comes after
    entries = reorder_partners(entries, state)

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

          # Create person and partner-separator nodes
          person_nodes =
            people
            |> Enum.with_index()
            |> Enum.map(fn {entry, idx} ->
              col = start_col + idx

              if Map.get(entry, :separator) do
                %GraphNode{
                  id: entry.separator_id,
                  type: :separator,
                  col: col,
                  row: row_idx
                }
              else
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
              end
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

  # ── Post-traversal corrections ───────────────────────────────────────

  # Fix has_more_down: if ALL of a person's children are already visited
  # (present in the DAG), they shouldn't show a "has more descendants" indicator.
  defp fix_has_more_indicators(entries, state) do
    Map.new(entries, fn {gen, people} ->
      corrected =
        Enum.map(people, fn entry ->
          cond do
            Map.get(entry, :separator) ->
              entry

            entry.has_more_down ->
              children = FamilyGraph.children(state.graph, entry.person.id)

              all_shown =
                children != [] and
                  Enum.all?(children, &Map.has_key?(state.visited, &1.id))

              %{entry | has_more_down: not all_shown}

            true ->
              entry
          end
        end)

      {gen, corrected}
    end)
  end

  # Reorder partners within each generation so that:
  # [ex-partners...] [previous-partners...] [PERSON] [current-partner]
  defp reorder_partners(entries, state) do
    couple_edges = Enum.filter(state.edges, &(&1.type in [:current_partner, :previous_partner]))
    partner_map = build_partner_map(couple_edges)

    Map.new(entries, fn {gen, people} ->
      {gen, reorder_generation(people, partner_map)}
    end)
  end

  defp build_partner_map(couple_edges) do
    Enum.reduce(couple_edges, %{}, fn edge, acc ->
      from_id = extract_person_id(edge.from_id)
      to_id = extract_person_id(edge.to_id)
      from_dup = String.ends_with?(edge.from_id, "-dup")
      to_dup = String.ends_with?(edge.to_id, "-dup")

      category = if edge.type == :current_partner, do: :current, else: :previous

      acc =
        if from_id && !from_dup do
          update_in(acc, [Access.key(from_id, %{current: [], previous: []})], fn map ->
            Map.update!(map, category, &[{to_id, to_dup} | &1])
          end)
        else
          acc
        end

      if to_id && !to_dup do
        update_in(acc, [Access.key(to_id, %{current: [], previous: []})], fn map ->
          Map.update!(map, category, &[{from_id, from_dup} | &1])
        end)
      else
        acc
      end
    end)
  end

  defp reorder_generation(people, partner_map) do
    # Extract separator entries and reorder only person entries
    {separators, person_entries} = Enum.split_with(people, &Map.get(&1, :separator))

    person_id_to_indices =
      person_entries
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {entry, idx}, acc ->
        Map.update(acc, entry.person.id, [idx], &[idx | &1])
      end)

    placed = MapSet.new()

    {groups, placed} =
      build_partner_groups(person_entries, partner_map, person_id_to_indices, placed)

    remaining =
      person_entries
      |> Enum.with_index()
      |> Enum.reject(fn {_entry, idx} -> MapSet.member?(placed, idx) end)
      |> Enum.map(fn {entry, _idx} -> entry end)

    reordered = rebuild_generation(person_entries, groups, placed, remaining)

    # Re-insert separators after their associated former partner
    reinsert_separators(reordered, separators)
  end

  # Insert each separator right after the entry for its associated partner.
  # The separator_id is "sep-{person_id}-{partner_id}" — the partner entry
  # (identified by partner_id) should precede the separator in the final order.
  defp reinsert_separators(entries, []), do: entries

  defp reinsert_separators(entries, separators) do
    # Build a map: partner_id -> list of separator entries to insert after that partner
    sep_by_partner =
      Enum.group_by(separators, fn sep ->
        # separator_id is "sep-{person_id}-{partner_id}"
        case String.split(sep.separator_id, "-") do
          ["sep", _person_id, partner_id] -> String.to_integer(partner_id)
          _ -> nil
        end
      end)

    Enum.flat_map(entries, fn entry ->
      seps = Map.get(sep_by_partner, entry.person.id, [])
      [entry | seps]
    end)
  end

  defp build_partner_groups(people, partner_map, person_id_to_indices, placed) do
    people
    |> Enum.with_index()
    |> Enum.reduce({[], placed}, fn {entry, idx}, {groups, placed} ->
      if MapSet.member?(placed, idx) or entry.duplicated or Map.get(entry, :separator) do
        {groups, placed}
      else
        case Map.get(partner_map, entry.person.id) do
          nil ->
            {groups, placed}

          %{current: current_partners, previous: previous_partners} ->
            prev_entries =
              find_partner_entries(previous_partners, people, person_id_to_indices, placed)

            curr_entries =
              find_partner_entries(current_partners, people, person_id_to_indices, placed)

            if prev_entries == [] and curr_entries == [] do
              {groups, placed}
            else
              prev_indices = Enum.map(prev_entries, fn {_e, i} -> i end)
              curr_indices = Enum.map(curr_entries, fn {_e, i} -> i end)

              placed =
                [idx | prev_indices ++ curr_indices]
                |> Enum.reduce(placed, &MapSet.put(&2, &1))

              group =
                Enum.map(prev_entries, fn {e, _i} -> e end) ++
                  [entry] ++
                  Enum.map(curr_entries, fn {e, _i} -> e end)

              {groups ++ [{idx, group}], placed}
            end
        end
      end
    end)
  end

  defp find_partner_entries(partner_ids, people, person_id_to_indices, placed) do
    Enum.flat_map(partner_ids, fn {partner_id, partner_dup} ->
      indices = Map.get(person_id_to_indices, partner_id, [])

      Enum.filter(indices, fn idx ->
        entry = Enum.at(people, idx)
        not MapSet.member?(placed, idx) and entry.duplicated == partner_dup
      end)
      |> Enum.map(fn idx -> {Enum.at(people, idx), idx} end)
    end)
    |> Enum.uniq_by(fn {_entry, idx} -> idx end)
  end

  defp rebuild_generation(people, groups, placed, remaining) do
    group_map = Map.new(groups)
    remaining_queue = :queue.from_list(remaining)

    {result, remaining_queue} =
      people
      |> Enum.with_index()
      |> Enum.reduce({[], remaining_queue}, fn {_entry, idx}, {acc, rq} ->
        cond do
          Map.has_key?(group_map, idx) ->
            {acc ++ Map.get(group_map, idx), rq}

          MapSet.member?(placed, idx) ->
            {acc, rq}

          true ->
            case :queue.out(rq) do
              {{:value, e}, rq2} -> {acc ++ [e], rq2}
              {:empty, rq2} -> {acc, rq2}
            end
        end
      end)

    result ++ :queue.to_list(remaining_queue)
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
end
