defmodule Ancestry.Kinship do
  @moduledoc """
  Calculates kinship relationships between two people using bidirectional BFS
  to find the Most Recent Common Ancestor (MRCA), then classifies the relationship
  based on generational distance from each person to the MRCA.
  """

  alias Ancestry.Kinship.BloodRelationshipLabel, as: Label
  alias Ancestry.People
  alias Ancestry.Relationships

  @max_depth 10

  defstruct [:relationship, :steps_a, :steps_b, :path, :mrca, :half?, :dna_percentage]

  @doc """
  Calculates the approximate percentage of shared DNA between two people
  based on their generational distances from the Most Recent Common Ancestor.

  Returns a float percentage (e.g. 50.0 for parent/child).
  """
  def dna_percentage(steps_a, steps_b, half?) do
    base =
      cond do
        # Direct line (one side is the MRCA)
        steps_a == 0 or steps_b == 0 ->
          100.0 / :math.pow(2, max(steps_a, steps_b))

        # Siblings (special case — share both parents)
        steps_a == 1 and steps_b == 1 ->
          50.0

        # Collateral relatives
        true ->
          100.0 / :math.pow(2, steps_a + steps_b - 1)
      end

    if half?, do: base / 2, else: base
  end

  @doc """
  Calculates the kinship relationship between two people.

  Returns `{:ok, %Kinship{}}` with the relationship details,
  or `{:error, :same_person}` if the IDs match,
  or `{:error, :no_common_ancestor}` if BFS exhausts max depth.
  """
  def calculate(person_a_id, person_b_id, _graph) do
    calculate(person_a_id, person_b_id)
  end

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

      person_a = People.get_person!(person_a_id)
      mrca = People.get_person!(mrca_id)
      half? = half_relationship?(mrca_id, steps_a, steps_b, ancestors_a, ancestors_b)
      relationship = Label.format(steps_a, steps_b, half?, person_a.gender)
      path = build_path(path_a, path_b, steps_a, steps_b)
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

  @doc """
  Build an ancestor map using BFS. Returns %{person_id => {depth, path_from_start}}
  where path_from_start is the list of person IDs from the starting person to this ancestor.
  """
  def build_ancestor_map(person_id) do
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
      label = path_label(index, steps_a, steps_b, person.gender)
      %{person: person, label: label}
    end)
  end

  defp path_label(0, _steps_a, _steps_b, _gender), do: "-"

  defp path_label(index, steps_a, _steps_b, gender) when index <= steps_a do
    # Going up from person A toward MRCA
    Label.format(0, index, false, gender)
  end

  defp path_label(index, steps_a, _steps_b, gender) do
    down_steps = index - steps_a

    cond do
      # Direct descendant path (person A is the MRCA)
      steps_a == 0 ->
        Label.format(down_steps, 0, false, gender)

      # Collateral: what this intermediate person is TO person A
      true ->
        Label.format(down_steps, steps_a, false, gender)
    end
  end
end
