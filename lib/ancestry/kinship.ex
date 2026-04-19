defmodule Ancestry.Kinship do
  @moduledoc """
  Orchestrates kinship calculations: tries blood kinship first,
  falls back to in-law detection. Owns shared primitives (BFS, DNA%).
  """

  alias Ancestry.Kinship.Blood
  alias Ancestry.People.FamilyGraph

  @max_depth 10

  defstruct [:relationship, :steps_a, :steps_b, :path, :mrca, :half?, :dna_percentage]

  @doc """
  Calculates the approximate percentage of shared DNA between two people
  based on their generational distances from the Most Recent Common Ancestor.
  """
  def dna_percentage(steps_a, steps_b, half?) do
    base =
      cond do
        steps_a == 0 or steps_b == 0 ->
          100.0 / :math.pow(2, max(steps_a, steps_b))

        steps_a == 1 and steps_b == 1 ->
          50.0

        true ->
          100.0 / :math.pow(2, steps_a + steps_b - 1)
      end

    if half?, do: base / 2, else: base
  end

  @doc """
  Calculates the kinship relationship between two people using a pre-built graph.

  Returns `{:ok, %Kinship{}}` for blood relatives,
  `{:error, :same_person}` if the IDs match,
  or `{:error, :no_common_ancestor}` if BFS exhausts max depth.

  Note: The orchestrator fallback to InLaw will be added in a later commit.
  Currently delegates directly to Blood.calculate/3.
  """
  def calculate(person_a_id, person_b_id, _graph) when person_a_id == person_b_id do
    {:error, :same_person}
  end

  def calculate(person_a_id, person_b_id, %FamilyGraph{} = graph) do
    Blood.calculate(person_a_id, person_b_id, graph)
  end

  @doc """
  Build an ancestor map using graph-aware BFS.
  Returns %{person_id => {depth, path_from_start}}.
  """
  def build_ancestor_map(person_id, %FamilyGraph{} = graph) do
    initial = %{person_id => {0, [person_id]}}
    bfs_expand([person_id], initial, 1, graph)
  end

  defp bfs_expand(_frontier, ancestors, depth, _graph) when depth > @max_depth,
    do: ancestors

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

  # --- Temporary: keep old DB-based BFS for InLaw until Task 4 migrates it ---

  alias Ancestry.Relationships

  @doc false
  def build_ancestor_map(person_id) do
    initial = %{person_id => {0, [person_id]}}
    legacy_bfs_expand([person_id], initial, 1)
  end

  defp legacy_bfs_expand(_frontier, ancestors, depth) when depth > @max_depth, do: ancestors
  defp legacy_bfs_expand([], ancestors, _depth), do: ancestors

  defp legacy_bfs_expand(frontier, ancestors, depth) do
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

    legacy_bfs_expand(new_frontier_ids, new_ancestors, depth + 1)
  end
end
