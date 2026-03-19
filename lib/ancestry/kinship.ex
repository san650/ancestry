defmodule Ancestry.Kinship do
  @moduledoc """
  Calculates kinship relationships between two people using bidirectional BFS
  to find the Most Recent Common Ancestor (MRCA), then classifies the relationship
  based on generational distance from each person to the MRCA.
  """

  alias Ancestry.People
  alias Ancestry.Relationships

  @max_depth 10

  defstruct [:relationship, :steps_a, :steps_b, :path, :mrca, :half?]

  @doc """
  Calculates the kinship relationship between two people.

  Returns `{:ok, %Kinship{}}` with the relationship details,
  or `{:error, :same_person}` if the IDs match,
  or `{:error, :no_common_ancestor}` if BFS exhausts max depth.
  """
  def calculate(person_a_id, person_b_id) when person_a_id == person_b_id do
    {:error, :same_person}
  end

  def calculate(person_a_id, person_b_id) do
    ancestors_a = build_ancestor_map(person_a_id)
    ancestors_b = build_ancestor_map(person_b_id)

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

      mrca = People.get_person!(mrca_id)
      half? = half_relationship?(mrca_id, steps_a, steps_b, ancestors_a, ancestors_b)
      relationship = classify(steps_a, steps_b, half?)
      path = build_path(path_a, path_b, steps_a, steps_b)

      {:ok,
       %__MODULE__{
         relationship: relationship,
         steps_a: steps_a,
         steps_b: steps_b,
         path: path,
         mrca: mrca,
         half?: half?
       }}
    end
  end

  # Build an ancestor map using BFS. Returns %{person_id => {depth, path_from_start}}
  # where path_from_start is the list of person IDs from the starting person to this ancestor.
  defp build_ancestor_map(person_id) do
    initial = %{person_id => {0, [person_id]}}
    bfs_expand([person_id], initial, 1)
  end

  defp bfs_expand(_frontier, ancestors, depth) when depth > @max_depth, do: ancestors
  defp bfs_expand([], ancestors, _depth), do: ancestors

  defp bfs_expand(frontier, ancestors, depth) do
    next_frontier =
      frontier
      |> Enum.flat_map(fn person_id ->
        Relationships.get_parents(person_id)
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

    bfs_expand(new_frontier_ids, new_ancestors, depth + 1)
  end

  # Determine if the relationship is a half-relationship.
  # For collateral relationships: check if both persons share two common ancestors
  # at the MRCA generation (both parents = full) or just one (half).
  defp half_relationship?(_mrca_id, steps_a, steps_b, _ancestors_a, _ancestors_b)
       when steps_a == 0 or steps_b == 0 do
    false
  end

  defp half_relationship?(_mrca_id, steps_a, steps_b, ancestors_a, ancestors_b) do
    common_at_mrca_depth =
      ancestors_a
      |> Map.keys()
      |> MapSet.new()
      |> MapSet.intersection(MapSet.new(Map.keys(ancestors_b)))
      |> Enum.count(fn id ->
        {da, _} = Map.fetch!(ancestors_a, id)
        {db, _} = Map.fetch!(ancestors_b, id)
        da == steps_a and db == steps_b
      end)

    common_at_mrca_depth < 2
  end

  # Classify the relationship based on steps from each person to the MRCA.
  defp classify(steps_a, steps_b, half?) do
    cond do
      steps_a == 0 and steps_b == 1 ->
        "Parent"

      steps_a == 0 and steps_b == 2 ->
        "Grandparent"

      steps_a == 0 and steps_b >= 3 ->
        ancestor_label(steps_b)

      steps_b == 0 and steps_a == 1 ->
        "Child"

      steps_b == 0 and steps_a == 2 ->
        "Grandchild"

      steps_b == 0 and steps_a >= 3 ->
        descendant_label(steps_a)

      steps_a == 1 and steps_b == 1 and half? ->
        "Half-Sibling"

      steps_a == 1 and steps_b == 1 ->
        "Sibling"

      steps_a == 1 and steps_b == 2 ->
        "Uncle & Aunt"

      steps_a == 1 and steps_b == 3 ->
        "Great Uncle & Aunt"

      steps_a == 1 and steps_b == 4 ->
        "Great Grand Uncle & Aunt"

      steps_a == 1 and steps_b >= 5 ->
        "#{numeric_ordinal(steps_b - 4)} Great Grand Uncle & Aunt"

      steps_a == 2 and steps_b == 1 ->
        "Nephew & Niece"

      steps_a == 3 and steps_b == 1 ->
        "Grand Nephew & Niece"

      steps_a == 4 and steps_b == 1 ->
        "Great Grand Nephew & Niece"

      steps_a >= 5 and steps_b == 1 ->
        "#{numeric_ordinal(steps_a - 4)} Great Grand Nephew & Niece"

      true ->
        half_prefix = if(half?, do: "Half-", else: "")
        "#{half_prefix}#{cousin_label(steps_a, steps_b)}"
    end
  end

  defp ancestor_label(steps) do
    greats = steps - 2

    cond do
      greats == 1 -> "Great Grandparent"
      greats == 2 -> "Great Great Grandparent"
      greats >= 3 -> "#{numeric_ordinal(greats)} Great Grandparent"
    end
  end

  defp descendant_label(steps) do
    greats = steps - 2

    cond do
      greats == 1 -> "Great Grandchild"
      greats == 2 -> "Great Great Grandchild"
      greats >= 3 -> "#{numeric_ordinal(greats)} Great Grandchild"
    end
  end

  defp cousin_label(steps_a, steps_b) do
    degree = min(steps_a, steps_b) - 1
    removed = abs(steps_a - steps_b)
    degree_str = ordinal(degree)

    removed_str =
      cond do
        removed == 0 -> ""
        removed == 1 -> ", Once Removed"
        removed == 2 -> ", Twice Removed"
        true -> ", #{removed} Times Removed"
      end

    "#{degree_str} Cousin#{removed_str}"
  end

  defp ordinal(1), do: "First"
  defp ordinal(2), do: "Second"
  defp ordinal(3), do: "Third"
  defp ordinal(4), do: "Fourth"
  defp ordinal(5), do: "Fifth"
  defp ordinal(6), do: "Sixth"
  defp ordinal(7), do: "Seventh"
  defp ordinal(8), do: "Eighth"
  defp ordinal(n), do: "#{n}th"

  defp numeric_ordinal(1), do: "1st"
  defp numeric_ordinal(2), do: "2nd"
  defp numeric_ordinal(3), do: "3rd"
  defp numeric_ordinal(n) when rem(n, 10) == 1 and rem(n, 100) != 11, do: "#{n}st"
  defp numeric_ordinal(n) when rem(n, 10) == 2 and rem(n, 100) != 12, do: "#{n}nd"
  defp numeric_ordinal(n) when rem(n, 10) == 3 and rem(n, 100) != 13, do: "#{n}rd"
  defp numeric_ordinal(n), do: "#{n}th"

  # Build the full path from person A through MRCA down to person B.
  defp build_path(path_a, path_b, steps_a, steps_b) do
    # path_a goes from person_a up to MRCA (inclusive)
    # path_b goes from person_b up to MRCA (inclusive)
    # We want: path_a ++ reverse(path_b) without duplicating MRCA
    path_b_descending =
      path_b
      |> Enum.reverse()
      |> tl()

    full_ids = path_a ++ path_b_descending

    full_ids
    |> Enum.with_index()
    |> Enum.map(fn {id, index} ->
      person = People.get_person!(id)
      label = path_label(index, steps_a, steps_b)
      %{person: person, label: label}
    end)
  end

  defp path_label(0, _steps_a, _steps_b), do: "Self"

  defp path_label(index, steps_a, _steps_b) when index <= steps_a do
    ascending_label(index)
  end

  defp path_label(index, steps_a, steps_b) do
    down_steps = index - steps_a
    descending_label(steps_a, steps_b, down_steps)
  end

  # Labels for going up (from person A toward MRCA)
  defp ascending_label(1), do: "Parent"
  defp ascending_label(2), do: "Grandparent"
  defp ascending_label(3), do: "Great Grandparent"
  defp ascending_label(4), do: "Great Great Grandparent"

  defp ascending_label(n) when n >= 5 do
    "#{numeric_ordinal(n - 2)} Great Grandparent"
  end

  # Labels for going down from MRCA toward person B.
  # Each intermediate person's relationship to Person A is determined by
  # Person A's distance to MRCA (steps_a) and that person's distance from MRCA (down_steps).
  # We reuse classify/3 to get the correct label for each position.
  defp descending_label(steps_a, _steps_b, down_steps) do
    cond do
      # Direct descendant path (person A is the MRCA)
      steps_a == 0 ->
        child_label(down_steps)

      # For collateral relationships, classify what this intermediate person
      # is TO Person A. The intermediate person is down_steps from MRCA,
      # Person A is steps_a from MRCA. We swap the arguments because classify/3
      # returns what the first person is to the second, but we want the label
      # from Person A's perspective (what the node is to Person A).
      true ->
        classify(down_steps, steps_a, false)
    end
  end

  defp child_label(1), do: "Child"
  defp child_label(2), do: "Grandchild"
  defp child_label(3), do: "Great Grandchild"
  defp child_label(4), do: "Great Great Grandchild"

  defp child_label(n) when n >= 5 do
    "#{numeric_ordinal(n - 2)} Great Grandchild"
  end
end
