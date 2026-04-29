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
  # Walks a family-unit tree top-down and assigns column/row coordinates.
  # Returns a flat list of placement tuples:
  #   {:placed_anchor, entry, col, row} — a person occupying (col, row)
  #   {:separator, col, row}            — an empty cell at (col, row)
  #
  # Arguments:
  #   root_unit  — %Couple{} or %Single{} (root of the half-tree)
  #   base_row   — row at which root_unit's anchor sits
  #   direction  — :descendant (children rows = row+1) or :ancestor (children rows = row-1)
  def __place_half__(root_unit, base_row, direction) do
    total_width = __width__(root_unit)

    do_place(root_unit, 0, base_row, total_width, direction, [])
    |> Enum.reverse()
  end

  # ── Placement private implementation ────────────────────────────────

  # Place a %Couple{} unit within [start_col..start_col+width-1] at `row`.
  defp do_place(%Couple{} = unit, start_col, row, width, direction, acc) do
    {lane_width, lane_acc} = place_loose_lane(unit.loose_lane, start_col, row, direction, acc)

    # Compute the remaining range after the loose lane (+ separator if lane present)
    {remaining_start, remaining_width} =
      remaining_range(start_col, width, lane_width, unit.loose_lane)

    # Center the couple's 2 cells within the remaining range
    anchor_a_col = remaining_start + div(remaining_width - 2, 2)
    anchor_b_col = anchor_a_col + 1

    acc2 =
      [
        {:placed_anchor, unit.anchor_a, anchor_a_col, row},
        {:placed_anchor, unit.anchor_b, anchor_b_col, row}
        | lane_acc
      ]

    # Fill the rest of this row (within [start_col..start_col+width-1]) with separators.
    occupied = MapSet.new([anchor_a_col, anchor_b_col])

    lane_cols =
      if unit.loose_lane && lane_width > 0 do
        MapSet.new(start_col..(start_col + lane_width - 1))
      else
        MapSet.new()
      end

    filled = MapSet.union(occupied, lane_cols)

    acc3 =
      Enum.reduce(start_col..(start_col + width - 1), acc2, fn col, a ->
        if MapSet.member?(filled, col), do: a, else: [{:separator, col, row} | a]
      end)

    # Recurse into children on the next row
    child_row = next_row(row, direction)
    place_children(unit.children, start_col, child_row, width, direction, acc3)
  end

  # Place a %Single{anchor: nil} (solo group) — no anchor cell, just lay out children.
  defp do_place(%Single{anchor: nil, children: kids}, start_col, row, width, direction, acc) do
    # No anchor on this row — all cells are separators.
    acc2 =
      Enum.reduce(start_col..(start_col + width - 1), acc, fn col, a ->
        [{:separator, col, row} | a]
      end)

    child_row = next_row(row, direction)
    place_children(kids, start_col, child_row, width, direction, acc2)
  end

  # Place a %Single{} unit with a real anchor.
  defp do_place(%Single{} = unit, start_col, row, width, direction, acc) do
    {lane_width, lane_acc} = place_loose_lane(unit.loose_lane, start_col, row, direction, acc)

    {remaining_start, remaining_width} =
      remaining_range(start_col, width, lane_width, unit.loose_lane)

    # Single anchor centered (floor) within remaining range
    anchor_col = remaining_start + div(remaining_width - 1, 2)

    acc2 = [{:placed_anchor, unit.anchor, anchor_col, row} | lane_acc]

    # Fill remaining row cells with separators
    occupied = MapSet.new([anchor_col])

    lane_cols =
      if unit.loose_lane && lane_width > 0 do
        MapSet.new(start_col..(start_col + lane_width - 1))
      else
        MapSet.new()
      end

    filled = MapSet.union(occupied, lane_cols)

    acc3 =
      Enum.reduce(start_col..(start_col + width - 1), acc2, fn col, a ->
        if MapSet.member?(filled, col), do: a, else: [{:separator, col, row} | a]
      end)

    child_row = next_row(row, direction)
    place_children(unit.children, start_col, child_row, width, direction, acc3)
  end

  # Place the loose lane units left-to-right within [start_col..start_col+lane_width-1].
  # Returns {lane_width, updated_acc}.
  defp place_loose_lane(nil, _start_col, _row, _direction, acc), do: {0, acc}
  defp place_loose_lane(%LooseLane{units: []}, _start_col, _row, _direction, acc), do: {0, acc}

  defp place_loose_lane(%LooseLane{units: units}, start_col, row, direction, acc) do
    lane_width = __width__(%LooseLane{units: units})
    {_final_col, final_acc} = place_units_in_row(units, start_col, row, direction, acc)
    {lane_width, final_acc}
  end

  # Lay out a list of units left-to-right on `row`, with one separator between adjacent units.
  # Returns {next_available_col, updated_acc}.
  defp place_units_in_row([], current_col, _row, _direction, acc), do: {current_col, acc}

  defp place_units_in_row([unit | rest], current_col, row, direction, acc) do
    unit_width = __width__(unit)
    acc2 = do_place(unit, current_col, row, unit_width, direction, acc)

    case rest do
      [] ->
        {current_col + unit_width, acc2}

      _ ->
        # Emit inter-unit separator then continue
        sep_col = current_col + unit_width
        acc3 = [{:separator, sep_col, row} | acc2]
        place_units_in_row(rest, sep_col + 1, row, direction, acc3)
    end
  end

  # Place the children of a unit in the given row, left-to-right with separators between.
  # children_start_col is the leftmost column owned by the parent.
  defp place_children([], _start_col, _child_row, _parent_width, _direction, acc), do: acc

  defp place_children(children, start_col, child_row, _parent_width, direction, acc) do
    {_final_col, final_acc} = place_units_in_row(children, start_col, child_row, direction, acc)
    final_acc
  end

  # Compute the remaining start column and width after accounting for a loose lane.
  # If no lane (or zero-width lane): remaining = full range.
  # If lane present: remaining_start = start_col + lane_width + 1 (lane + separator)
  defp remaining_range(start_col, total_width, lane_width, loose_lane) do
    if loose_lane && lane_width > 0 do
      remaining_start = start_col + lane_width + 1
      remaining_width = total_width - lane_width - 1
      {remaining_start, remaining_width}
    else
      {start_col, total_width}
    end
  end

  # Compute the next row given a direction.
  defp next_row(row, :descendant), do: row + 1
  defp next_row(row, :ancestor), do: row - 1

  @doc false
  # Exposed for testing via __name__ convention.
  # Computes the width (in grid columns) for a family unit.
  # Width rules:
  #   - Leaf %Single{} = 1, leaf %Couple{} = 2
  #   - %Single{anchor: nil} (solo group) = children_width (no floor)
  #   - %Single{} with kids = max(1, children_width(kids))
  #   - %Couple{} with kids = max(2, children_width(kids))
  #   - When loose_lane is set: add 1 (separator) + width(loose_lane) to primary width
  #   - %LooseLane{} = sum of unit widths + (count - 1) separators
  def __width__(%LooseLane{units: []}), do: 0

  def __width__(%LooseLane{units: [only]}), do: __width__(only)

  def __width__(%LooseLane{units: units}) do
    Enum.sum(Enum.map(units, &__width__/1)) + length(units) - 1
  end

  def __width__(%Single{anchor: nil, children: kids}) do
    children_width(kids)
  end

  def __width__(%Single{children: [], loose_lane: nil}), do: 1

  def __width__(%Single{children: [], loose_lane: lane}) do
    lane_w = __width__(lane)
    if lane_w == 0, do: 1, else: 1 + 1 + lane_w
  end

  def __width__(%Single{children: kids, loose_lane: nil}) do
    max(1, children_width(kids))
  end

  def __width__(%Single{children: kids, loose_lane: lane}) do
    primary_w = max(1, children_width(kids))
    lane_w = __width__(lane)
    if lane_w == 0, do: primary_w, else: primary_w + 1 + lane_w
  end

  def __width__(%Couple{children: [], loose_lane: nil}), do: 2

  def __width__(%Couple{children: [], loose_lane: lane}) do
    lane_w = __width__(lane)
    if lane_w == 0, do: 2, else: 2 + 1 + lane_w
  end

  def __width__(%Couple{children: kids, loose_lane: nil}) do
    max(2, children_width(kids))
  end

  def __width__(%Couple{children: kids, loose_lane: lane}) do
    primary_w = max(2, children_width(kids))
    lane_w = __width__(lane)
    if lane_w == 0, do: primary_w, else: primary_w + 1 + lane_w
  end

  defp children_width([]), do: 0
  defp children_width([only]), do: __width__(only)

  defp children_width([first | rest]) do
    __width__(first) + 1 + children_width(rest)
  end

  @doc false
  # Exposed for testing via __name__ convention.
  # Merges descendant placements and ancestor placements into a single coordinate system.
  #
  # Both halves were independently laid out with __place_half__/3 starting at base_row 0.
  # This function:
  #   1. Finds the focus person's column in desc_placements (anchor_a of focus couple, or focus single).
  #   2. Finds the ancestor root couple/single's leftmost column at row 0 in anc_placements.
  #   3. Computes delta = desc_focus_col - anc_parent_col.
  #   4. If delta >= 0: shift ancestor placements right by delta. Descendants stay.
  #      If delta < 0: shift descendant placements right by -delta. Ancestors stay.
  #   5. Shifts every ancestor placement's row by -1 (so parents land at row -1 above focus).
  #   6. Returns the combined list.
  def __merge_halves__(desc_placements, anc_placements) do
    desc_focus_col = focus_col(desc_placements)
    anc_parent_col = anc_parent_col(anc_placements)
    delta = desc_focus_col - anc_parent_col

    {shifted_desc, shifted_anc} =
      if delta >= 0 do
        # Shift ancestors right by delta; descendants unchanged
        anc_shifted = Enum.map(anc_placements, &shift_placement(&1, delta, -1))
        {desc_placements, anc_shifted}
      else
        # Shift descendants right by -delta; ancestors unchanged (only row shift)
        desc_shifted = Enum.map(desc_placements, &shift_placement(&1, -delta, 0))
        anc_shifted = Enum.map(anc_placements, &shift_placement(&1, 0, -1))
        {desc_shifted, anc_shifted}
      end

    shifted_desc ++ shifted_anc
  end

  # Find the column of the focus person in desc_placements.
  # The focus entry has focus: true. Returns the column of the focus anchor,
  # defaulting to 0 if not found.
  defp focus_col(desc_placements) do
    Enum.find_value(desc_placements, 0, fn
      {:placed_anchor, %{focus: true}, col, _row} -> col
      _ -> nil
    end)
  end

  # Find the leftmost column of the ancestor root unit's anchor at row 0.
  # This is the minimum column among all :placed_anchor tuples at row 0.
  # Defaults to 0 if none found.
  defp anc_parent_col(anc_placements) do
    anc_placements
    |> Enum.filter(fn
      {:placed_anchor, _entry, _col, 0} -> true
      _ -> false
    end)
    |> Enum.map(fn {:placed_anchor, _entry, col, _row} -> col end)
    |> Enum.min(fn -> 0 end)
  end

  # Shift a placement tuple by (dcol, drow).
  defp shift_placement({:placed_anchor, entry, col, row}, dcol, drow),
    do: {:placed_anchor, entry, col + dcol, row + drow}

  defp shift_placement({:separator, col, row}, dcol, drow),
    do: {:separator, col + dcol, row + drow}

  @doc false
  # Exposed for testing via __name__ convention.
  # Builds the descendant-side family-unit tree rooted at the focus's primary
  # couple (or single) unit. Walks gen ≤ 0 entries from Phase 1.
  def __build_descendant_tree__(state, focus_id) do
    focus_entry = find_entry(state, focus_id, 0)
    build_descendant_unit(focus_id, focus_entry, state)
  end

  @doc false
  # Exposed for testing via __name__ convention.
  # Builds the ancestor-side family-unit tree for the focus person.
  # Returns the focus's parents' couple/single unit (gen 1), with children
  # being the upward subtrees (grandparents, great-grandparents, etc.).
  # Returns nil if the focus has no known parents.
  def __build_ancestor_tree__(state, focus_id) do
    parent_entries = find_parent_entries(state, focus_id)
    build_ancestor_root(parent_entries, state)
  end

  # ── Ancestor tree private implementation ────────────────────────────

  # Find all parent entries for a given focus person (via :parent_child edges
  # pointing TO the focus, from parents at gen 1).
  defp find_parent_entries(state, focus_id) do
    focus_node_id = "person-#{focus_id}"

    parent_ids =
      state.edges
      |> Enum.filter(fn edge ->
        edge.type == :parent_child and edge.to_id == focus_node_id
      end)
      |> Enum.map(fn edge -> extract_id(edge.from_id) end)
      |> Enum.reject(&is_nil/1)

    # Retrieve entries for these parent IDs at any gen >= 1
    Enum.flat_map(parent_ids, fn pid ->
      state.entries
      |> Enum.flat_map(fn {_gen, entries} -> entries end)
      |> Enum.filter(fn e -> e.person.id == pid end)
      |> Enum.take(1)
    end)
  end

  # Build the root ancestor unit (focus's parents' unit).
  defp build_ancestor_root([], _state), do: nil

  defp build_ancestor_root([single_parent], state) do
    # One parent: %Single{} with children = upward subtree of that parent
    children = build_ancestor_unit(single_parent, :left, state)
    %Single{anchor: single_parent, children: List.wrap(children) |> Enum.reject(&is_nil/1)}
  end

  defp build_ancestor_root([_p1, _p2] = parents, state) do
    {entry_a, entry_b} = order_parents_by_couple_edge(parents, state)

    subtree_a = build_ancestor_unit(entry_a, :left, state)
    subtree_b = build_ancestor_unit(entry_b, :right, state)

    children =
      [subtree_a, subtree_b]
      |> Enum.reject(&is_nil/1)

    %Couple{anchor_a: entry_a, anchor_b: entry_b, children: children}
  end

  defp build_ancestor_root(parents, state) do
    # More than 2 parents: take the first two (shouldn't happen in valid data)
    parents |> Enum.take(2) |> build_ancestor_root(state)
  end

  # Order two parent entries by looking for a couple edge between them.
  # The `from_id` person becomes anchor_a (left), `to_id` becomes anchor_b (right).
  # Falls back to insertion order if no couple edge found.
  defp order_parents_by_couple_edge([p1, p2], state) do
    p1_node = "person-#{p1.person.id}"
    p2_node = "person-#{p2.person.id}"

    couple_edge =
      Enum.find(state.edges, fn edge ->
        edge.type in [:current_partner, :previous_partner] and
          ((edge.from_id == p1_node and edge.to_id == p2_node) or
             (edge.from_id == p2_node and edge.to_id == p1_node))
      end)

    case couple_edge do
      nil ->
        {p1, p2}

      edge ->
        if extract_id(edge.from_id) == p1.person.id do
          {p1, p2}
        else
          {p2, p1}
        end
    end
  end

  # Build the ancestor unit for a single parent entry.
  # Returns a %Couple{} or %Single{} representing this parent's own parents,
  # or nil if no grandparents are known (or if parent is duplicated).
  # `side` is :left or :right — controls where laterals are placed in children.
  defp build_ancestor_unit(parent_entry, side, state) do
    # Duplicated entries are leaves — do not recurse upward
    if parent_entry.duplicated do
      nil
    else
      grandparent_entries = find_parent_entries(state, parent_entry.person.id)
      build_grandparent_unit(parent_entry, grandparent_entries, side, state)
    end
  end

  defp build_grandparent_unit(_parent_entry, [], _side, _state), do: nil

  defp build_grandparent_unit(parent_entry, [single_gp], side, state) do
    # One grandparent: recursively build their ancestor unit
    gp_children = build_ancestor_unit(single_gp, side, state)
    laterals = find_lateral_siblings(single_gp, parent_entry.person.id, state)
    lateral_units = build_lateral_units(laterals, state)

    children =
      arrange_laterals(lateral_units, List.wrap(gp_children) |> Enum.reject(&is_nil/1), side)

    %Single{anchor: single_gp, children: children}
  end

  defp build_grandparent_unit(parent_entry, [_gp1, _gp2] = gp_entries, side, state) do
    {gp_a, gp_b} = order_parents_by_couple_edge(gp_entries, state)

    # Recursively build each grandparent's own ancestors
    subtree_a = build_ancestor_unit(gp_a, :left, state)
    subtree_b = build_ancestor_unit(gp_b, :right, state)

    deeper_subtrees =
      [subtree_a, subtree_b]
      |> Enum.reject(&is_nil/1)

    # Find laterals: other children of (gp_a, gp_b) that are NOT the direct-line parent
    laterals = find_joint_lateral_siblings(gp_a, gp_b, parent_entry.person.id, state)
    lateral_units = build_lateral_units(laterals, state)

    children = arrange_laterals(lateral_units, deeper_subtrees, side)

    %Couple{anchor_a: gp_a, anchor_b: gp_b, children: children}
  end

  defp build_grandparent_unit(parent_entry, gp_entries, side, state) do
    # More than 2: take first two
    gp_entries |> Enum.take(2) |> then(&build_grandparent_unit(parent_entry, &1, side, state))
  end

  # Find lateral siblings of `direct_child_id` among children of `gp_entry`
  # (for the single-grandparent case).
  defp find_lateral_siblings(gp_entry, direct_child_id, state) do
    gp_node_id = "person-#{gp_entry.person.id}"
    child_gen = gp_entry.gen - 1

    child_ids =
      state.edges
      |> Enum.filter(fn edge ->
        edge.type == :parent_child and edge.from_id == gp_node_id
      end)
      |> Enum.map(fn edge -> extract_id(edge.to_id) end)
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == direct_child_id))

    Enum.flat_map(child_ids, fn cid ->
      case find_entry(state, cid, child_gen) do
        nil -> []
        entry -> [entry]
      end
    end)
  end

  # Find lateral siblings of `direct_child_id` among joint children of (gp_a, gp_b).
  defp find_joint_lateral_siblings(gp_a, gp_b, direct_child_id, state) do
    child_gen = gp_a.gen - 1
    child_entries = Map.get(state.entries, child_gen, [])

    Enum.filter(child_entries, fn entry ->
      cid = entry.person.id

      cid != direct_child_id and
        has_parent_edge?(state, gp_a.person.id, cid) and
        has_parent_edge?(state, gp_b.person.id, cid)
    end)
  end

  # Build lateral units. Laterals are leaves in the ancestor tree.
  # If a lateral has a current partner at the same gen, build a %Couple{} leaf;
  # otherwise build a %Single{} leaf.
  defp build_lateral_units(laterals, state) do
    laterals
    |> sort_laterals_by_birth_year()
    |> Enum.map(fn lat_entry ->
      partner_entry = find_current_partner(lat_entry.person.id, lat_entry.gen, state)

      case partner_entry do
        nil -> %Single{anchor: lat_entry, children: []}
        partner -> %Couple{anchor_a: lat_entry, anchor_b: partner, children: []}
      end
    end)
  end

  # Sort laterals by birth year (nils last).
  defp sort_laterals_by_birth_year(laterals) do
    Enum.sort_by(laterals, fn lat ->
      by = lat.person.birth_year
      {is_nil(by), by || 0}
    end)
  end

  # Arrange laterals around deeper subtrees based on side.
  # :left  → laterals go BEFORE the deeper subtrees
  # :right → laterals go AFTER the deeper subtrees
  defp arrange_laterals(lateral_units, deeper_subtrees, :left) do
    lateral_units ++ deeper_subtrees
  end

  defp arrange_laterals(lateral_units, deeper_subtrees, :right) do
    deeper_subtrees ++ lateral_units
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
