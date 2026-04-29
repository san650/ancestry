defmodule Ancestry.People.PersonGraph.Layout do
  @moduledoc """
  Bottom-up subtree-width allocation layout for `PersonGraph`.

  Consumes Phase-1 traversal output (entries grouped by generation + edges +
  focus_id) and produces a flat `(nodes, grid_cols, grid_rows)` triple ready
  to be returned from `PersonGraph.build/3`.

  See `docs/plans/2026-04-28-graph-clustering-design.md` for the algorithm.
  """

  defmodule Couple do
    @moduledoc false
    defstruct [:anchor_a, :anchor_b, children: [], loose_lane: nil]
  end

  defmodule Single do
    @moduledoc false
    defstruct [:anchor, children: [], loose_lane: nil]
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
    # Real implementation arrives in Tasks 3-7.
    {[], 0, 0}
  end

  @doc false
  # Exposed for testing via __name__ convention.
  # Builds the descendant-side family-unit tree rooted at the focus's primary
  # couple (or single) unit. Walks gen ≤ 0 entries from Phase 1.
  def __build_descendant_tree__(state, focus_id) do
    focus_entry = find_entry(state, focus_id, 0)
    build_descendant_unit(focus_id, focus_entry, state)
  end

  # ── Private implementation ───────────────────────────────────────────

  # Build the family unit for a given person (by id + entry) at their generation.
  # Recursion: for each child, call build_descendant_unit recursively.
  defp build_descendant_unit(person_id, person_entry, state) do
    # Duplicated entries are always leaves
    if person_entry.duplicated do
      %Single{anchor: person_entry, children: []}
    else
      person_gen = person_entry.gen
      current_partner_entry = find_current_partner(person_id, person_gen, state)

      case current_partner_entry do
        nil ->
          build_single_unit(person_id, person_entry, state)

        partner_entry ->
          build_couple_unit(person_id, person_entry, partner_entry, state)
      end
    end
  end

  # Build a %Single{} unit for a person with no current partner.
  defp build_single_unit(person_id, person_entry, state) do
    person_gen = person_entry.gen
    child_gen = person_gen - 1

    # Collect ex/previous partner entries at same gen
    ex_partner_ids = find_ex_partner_ids(person_id, person_entry.gen, state)

    # Joint children with each ex partner
    {loose_units, ex_child_ids} =
      build_ex_loose_units(person_id, ex_partner_ids, child_gen, state)

    # Solo children: only one parent_child edge, not joint with any ex
    solo_children = find_solo_children(person_id, child_gen, MapSet.new(ex_child_ids), state)

    solo_unit =
      if solo_children == [] do
        nil
      else
        solo_child_units =
          Enum.map(solo_children, fn child_entry ->
            build_descendant_unit(child_entry.person.id, child_entry, state)
          end)

        %Single{anchor: nil, children: solo_child_units}
      end

    all_loose_units = loose_units ++ if(solo_unit, do: [solo_unit], else: [])

    loose_lane =
      if all_loose_units == [] do
        nil
      else
        %LooseLane{units: all_loose_units}
      end

    %Single{anchor: person_entry, children: [], loose_lane: loose_lane}
  end

  # Build a %Couple{} unit for a person with a current partner.
  defp build_couple_unit(person_id, person_entry, partner_entry, state) do
    partner_id = partner_entry.person.id
    person_gen = person_entry.gen
    child_gen = person_gen - 1

    # Joint children of the primary couple
    joint_child_entries = find_joint_children(person_id, partner_id, child_gen, state)

    joint_child_units =
      Enum.map(joint_child_entries, fn child_entry ->
        build_descendant_unit(child_entry.person.id, child_entry, state)
      end)

    # Ex/previous partners and their joint children (loose lane)
    ex_partner_ids = find_ex_partner_ids(person_id, person_gen, state)

    # Exclude partner_id from ex partners (shouldn't happen but defensive)
    ex_partner_ids = Enum.reject(ex_partner_ids, &(&1 == partner_id))

    # The set of child IDs that are joint with the current partner
    primary_child_ids = MapSet.new(joint_child_entries, & &1.person.id)

    {loose_units, ex_child_ids} =
      build_ex_loose_units(person_id, ex_partner_ids, child_gen, state)

    # Solo children: only one parent_child edge, not joint with current OR any ex
    all_joint_ids = MapSet.union(primary_child_ids, MapSet.new(ex_child_ids))
    solo_children = find_solo_children(person_id, child_gen, all_joint_ids, state)

    solo_unit =
      if solo_children == [] do
        nil
      else
        solo_child_units =
          Enum.map(solo_children, fn child_entry ->
            build_descendant_unit(child_entry.person.id, child_entry, state)
          end)

        %Single{anchor: nil, children: solo_child_units}
      end

    all_loose_units = loose_units ++ if(solo_unit, do: [solo_unit], else: [])

    loose_lane =
      if all_loose_units == [] do
        nil
      else
        %LooseLane{units: all_loose_units}
      end

    %Couple{
      anchor_a: person_entry,
      anchor_b: partner_entry,
      children: joint_child_units,
      loose_lane: loose_lane
    }
  end

  # Build loose lane units for each ex/previous partner and their joint children.
  # Returns {[%Single{} units], [child_ids that belong to ex partners]}
  defp build_ex_loose_units(person_id, ex_partner_ids, child_gen, state) do
    Enum.reduce(ex_partner_ids, {[], []}, fn ex_id, {units, all_ex_child_ids} ->
      ex_entry = find_entry_by_id(state, ex_id)

      ex_joint_children = find_joint_children(person_id, ex_id, child_gen, state)

      ex_child_units =
        Enum.map(ex_joint_children, fn child_entry ->
          build_descendant_unit(child_entry.person.id, child_entry, state)
        end)

      ex_child_ids = Enum.map(ex_joint_children, & &1.person.id)

      unit = %Single{anchor: ex_entry, children: ex_child_units}
      {units ++ [unit], all_ex_child_ids ++ ex_child_ids}
    end)
  end

  # ── Edge / entry helpers ─────────────────────────────────────────────

  # Find the entry for `person_id` at generation `gen` (non-duplicated).
  defp find_entry(state, person_id, gen) do
    state.entries
    |> Map.get(gen, [])
    |> Enum.find(fn e -> e.person.id == person_id and not e.duplicated end)
  end

  # Find an entry for person_id anywhere in entries (first non-dup match).
  defp find_entry_by_id(state, person_id) do
    state.entries
    |> Enum.flat_map(fn {_gen, entries} -> entries end)
    |> Enum.find(fn e -> e.person.id == person_id and not e.duplicated end)
  end

  # Find the current partner entry for `person_id` at `person_gen`.
  # Current partner = connected via `:current_partner` edge at same gen.
  defp find_current_partner(person_id, person_gen, state) do
    person_node_id = "person-#{person_id}"

    partner_id =
      state.edges
      |> Enum.find_value(fn edge ->
        if edge.type == :current_partner do
          cond do
            edge.from_id == person_node_id -> extract_id(edge.to_id)
            edge.to_id == person_node_id -> extract_id(edge.from_id)
            true -> nil
          end
        end
      end)

    case partner_id do
      nil -> nil
      id -> find_entry(state, id, person_gen)
    end
  end

  # Find all ex/previous partner IDs for `person_id` at `person_gen`.
  defp find_ex_partner_ids(person_id, person_gen, state) do
    person_node_id = "person-#{person_id}"

    state.edges
    |> Enum.filter(&(&1.type == :previous_partner))
    |> Enum.flat_map(fn edge ->
      cond do
        edge.from_id == person_node_id -> [extract_id(edge.to_id)]
        edge.to_id == person_node_id -> [extract_id(edge.from_id)]
        true -> []
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(fn id ->
      # Must be at same generation
      Map.get(state.visited, id) == person_gen
    end)
  end

  # Find joint children of person_a and person_b at child_gen.
  # A joint child has parent_child edges from both person_a and person_b.
  defp find_joint_children(person_a_id, person_b_id, child_gen, state) do
    child_entries = Map.get(state.entries, child_gen, [])

    Enum.filter(child_entries, fn child_entry ->
      child_id = child_entry.person.id

      has_parent_edge?(state, person_a_id, child_id) and
        has_parent_edge?(state, person_b_id, child_id)
    end)
  end

  # Find solo children of person_id at child_gen.
  # Solo: has exactly one parent_child edge pointing to the child, and that
  # edge is from person_id. Excludes children already in `excluded_ids`.
  defp find_solo_children(person_id, child_gen, excluded_ids, state) do
    child_entries = Map.get(state.entries, child_gen, [])

    Enum.filter(child_entries, fn child_entry ->
      child_id = child_entry.person.id
      child_node_id = "person-#{child_id}"

      not MapSet.member?(excluded_ids, child_id) and
        has_parent_edge?(state, person_id, child_id) and
        count_parent_edges(state, child_node_id) == 1
    end)
  end

  defp has_parent_edge?(state, parent_id, child_id) do
    parent_node_id = "person-#{parent_id}"
    child_node_id = "person-#{child_id}"

    Enum.any?(state.edges, fn edge ->
      edge.type == :parent_child and
        edge.from_id == parent_node_id and
        edge.to_id == child_node_id
    end)
  end

  defp count_parent_edges(state, child_node_id) do
    Enum.count(state.edges, fn edge ->
      edge.type == :parent_child and edge.to_id == child_node_id
    end)
  end

  defp extract_id(node_id) do
    id_str =
      node_id
      |> String.replace_prefix("person-", "")
      |> String.replace_suffix("-dup", "")

    case Integer.parse(id_str) do
      {id, ""} -> id
      _ -> nil
    end
  end
end
