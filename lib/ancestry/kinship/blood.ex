defmodule Ancestry.Kinship.Blood do
  @moduledoc """
  Blood kinship algorithm: bidirectional BFS to find the MRCA,
  classify the relationship, and build the path.
  """

  alias Ancestry.Kinship
  alias Ancestry.Kinship.BloodRelationshipLabel
  alias Ancestry.People.FamilyGraph

  @doc """
  Calculates the blood kinship relationship between two people.

  Returns `{:ok, %Kinship{}}` or `{:error, :no_common_ancestor}`.
  """
  def calculate(person_a_id, person_b_id, %FamilyGraph{} = graph) do
    ancestors_a = Kinship.build_ancestor_map(person_a_id, graph)
    ancestors_b = Kinship.build_ancestor_map(person_b_id, graph)

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

      person_a = FamilyGraph.fetch_person!(graph, person_a_id)
      mrca = FamilyGraph.fetch_person!(graph, mrca_id)
      half? = half_relationship?(mrca_id, steps_a, steps_b, ancestors_a, ancestors_b)
      relationship = BloodRelationshipLabel.format(steps_a, steps_b, half?, person_a.gender)
      path = build_path(path_a, path_b, steps_a, steps_b, graph)
      dna_pct = Kinship.dna_percentage(steps_a, steps_b, half?)

      {:ok,
       %Kinship{
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

  defp build_path(path_a, path_b, steps_a, steps_b, graph) do
    path_b_descending =
      path_b
      |> Enum.reverse()
      |> tl()

    full_ids = path_a ++ path_b_descending

    full_ids
    |> Enum.with_index()
    |> Enum.map(fn {id, index} ->
      person = FamilyGraph.fetch_person!(graph, id)
      label = path_label(index, steps_a, steps_b, person.gender)
      %{person: person, label: label}
    end)
  end

  defp path_label(0, _steps_a, _steps_b, _gender), do: "-"

  defp path_label(index, steps_a, _steps_b, gender) when index <= steps_a do
    BloodRelationshipLabel.format(0, index, false, gender)
  end

  defp path_label(index, steps_a, _steps_b, gender) do
    down_steps = index - steps_a

    cond do
      steps_a == 0 ->
        BloodRelationshipLabel.format(down_steps, 0, false, gender)

      true ->
        BloodRelationshipLabel.format(down_steps, steps_a, false, gender)
    end
  end
end
