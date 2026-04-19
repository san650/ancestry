defmodule Ancestry.Kinship.InLaw do
  @moduledoc """
  Detects in-law relationships by partner-hopping when blood BFS finds no MRCA.

  Algorithm:
  1. Check if A and B are direct partners (spouse check).
  2. For each of A's partners, run blood BFS between that partner and B.
  3. For each of B's partners, run blood BFS between A and that partner.
  4. Pick the best result (lowest total steps; tiebreak: active partner type wins).
  5. Build the path and label.
  """

  alias Ancestry.Kinship
  alias Ancestry.Kinship.InLawLabel
  alias Ancestry.People
  alias Ancestry.Relationships
  alias Ancestry.Relationships.Relationship

  defstruct [:relationship, :partner_link, :path]

  @doc """
  Calculates an in-law relationship between two people.

  Returns `{:ok, %InLaw{}}` or `{:error, :no_relationship}`.
  """
  def calculate(person_a_id, person_b_id) do
    person_a = People.get_person!(person_a_id)
    person_b = People.get_person!(person_b_id)

    with {:error, :no_spouse} <- check_direct_spouse(person_a, person_b) do
      find_via_partner_hop(person_a, person_b)
    end
  end

  # --- Step 1: Direct spouse check ---

  defp check_direct_spouse(person_a, person_b) do
    case Relationships.get_partner_relationship(person_a.id, person_b.id) do
      nil ->
        {:error, :no_spouse}

      _rel ->
        relationship = InLawLabel.format(:spouse, :spouse, person_a.gender)

        path = [
          %{person: person_a, label: "-", partner_link?: false},
          %{person: person_b, label: "-", partner_link?: false}
        ]

        {:ok,
         %__MODULE__{
           relationship: relationship,
           partner_link: nil,
           path: path
         }}
    end
  end

  # --- Steps 2-5: Partner-hop BFS ---

  defp find_via_partner_hop(person_a, person_b) do
    a_side_results = hop_a_side(person_a, person_b)
    b_side_results = hop_b_side(person_a, person_b)

    all_results = a_side_results ++ b_side_results

    case pick_best(all_results) do
      nil ->
        {:error, :no_relationship}

      {steps_a, steps_b, path_ids, partner_person, side, _rel} ->
        relationship = InLawLabel.format(steps_a, steps_b, person_a.gender)

        path =
          build_in_law_path(
            path_ids,
            person_a,
            person_b,
            partner_person,
            side,
            steps_a,
            steps_b
          )

        {:ok,
         %__MODULE__{
           relationship: relationship,
           partner_link: %{person: partner_person, side: side},
           path: path
         }}
    end
  end

  # Hop through A's partners: BFS between each partner and B
  defp hop_a_side(person_a, person_b) do
    partners_of_a = Relationships.get_all_partners(person_a.id)
    ancestors_b = Kinship.build_ancestor_map(person_b.id)

    Enum.flat_map(partners_of_a, fn {partner, rel} ->
      ancestors_partner = Kinship.build_ancestor_map(partner.id)

      case find_mrca(ancestors_partner, ancestors_b) do
        nil ->
          []

        {steps_a, steps_b, path_partner, path_b} ->
          # path_ids: A -> partner -> up to MRCA -> down to B
          # steps_a here is from partner (A's partner) to MRCA
          # steps_b is from B to MRCA
          # We prepend person_a at the front
          path_ids = {person_a.id, path_partner, path_b}
          [{steps_a, steps_b, path_ids, partner, :a, rel}]
      end
    end)
  end

  # Hop through B's partners: BFS between A and each partner
  defp hop_b_side(person_a, person_b) do
    partners_of_b = Relationships.get_all_partners(person_b.id)
    ancestors_a = Kinship.build_ancestor_map(person_a.id)

    Enum.flat_map(partners_of_b, fn {partner, rel} ->
      ancestors_partner = Kinship.build_ancestor_map(partner.id)

      case find_mrca(ancestors_a, ancestors_partner) do
        nil ->
          []

        {steps_a, steps_b, path_a, path_partner} ->
          # path_ids: A -> up to MRCA -> down to B's partner -> B
          path_ids = {path_a, path_partner, person_b.id}
          [{steps_a, steps_b, path_ids, partner, :b, rel}]
      end
    end)
  end

  # Find the MRCA between two ancestor maps. Returns {steps_a, steps_b, path_a, path_b} or nil.
  defp find_mrca(ancestors_a, ancestors_b) do
    common_ancestor_ids =
      ancestors_a
      |> Map.keys()
      |> MapSet.new()
      |> MapSet.intersection(MapSet.new(Map.keys(ancestors_b)))

    if MapSet.size(common_ancestor_ids) == 0 do
      nil
    else
      {_mrca_id, steps_a, steps_b, path_a, path_b} =
        common_ancestor_ids
        |> Enum.map(fn id ->
          {da, pa} = Map.fetch!(ancestors_a, id)
          {db, pb} = Map.fetch!(ancestors_b, id)
          {id, da, db, pa, pb}
        end)
        |> Enum.min_by(fn {_id, da, db, _pa, _pb} -> da + db end)

      {steps_a, steps_b, path_a, path_b}
    end
  end

  # Pick the best candidate: lowest steps_a + steps_b, tiebreak: active > former
  defp pick_best([]), do: nil

  defp pick_best(candidates) do
    Enum.min_by(candidates, fn {steps_a, steps_b, _path_ids, _partner, _side, rel} ->
      total = steps_a + steps_b
      # active partner types are preferred (lower score)
      type_score = if Relationship.active_partner_type?(rel.type), do: 0, else: 1
      {total, type_score}
    end)
  end

  # Build the full path including the partner-hop node.
  #
  # For side :b — B is appended after the blood path (A → partner_of_B)
  #   path_ids = {path_a_to_mrca, path_partner_to_mrca, person_b_id}
  #   final path: [A, ..blood nodes..., partner, B]
  #   partner and B are marked partner_link?: true
  #   Blood labels use Label.format (what each person is TO person A)
  #   B gets the in-law label (what B is to A)
  #
  # For side :a — A is prepended before the blood path (partner_of_A → B)
  #   path_ids = {person_a_id, path_partner_to_mrca, path_b_to_mrca}
  #   final path: [A, partner, ..blood nodes..., B]
  #   A and partner are marked partner_link?: true
  defp build_in_law_path(path_ids, person_a, person_b, _partner_person, side, steps_a, steps_b) do
    case side do
      :b ->
        {path_a, path_partner, _b_id} = path_ids
        blood_ids = merge_blood_path(path_a, path_partner)

        # Blood nodes: labeled with what each person is TO person A
        blood_nodes =
          blood_ids
          |> Enum.with_index()
          |> Enum.map(fn {id, index} ->
            person = People.get_person!(id)
            label = blood_path_label(index, steps_a, steps_b, person.gender)
            is_last = index == length(blood_ids) - 1
            %{person: person, label: label, partner_link?: is_last}
          end)

        # B node: labeled with what B is to A (in-law, swapped coords, B's gender)
        b_label = InLawLabel.format(steps_b, steps_a, person_b.gender)

        blood_nodes ++
          [%{person: person_b, label: b_label, partner_link?: true}]

      :a ->
        {_a_id, path_partner, path_b} = path_ids
        blood_ids = merge_blood_path(path_partner, path_b)

        # Blood nodes: labeled with what each person is TO A's partner
        # (these are the partner's blood relatives, not A's)
        blood_nodes =
          blood_ids
          |> Enum.with_index()
          |> Enum.map(fn {id, index} ->
            person = People.get_person!(id)
            label = blood_path_label(index, steps_a, steps_b, person.gender)
            %{person: person, label: label, partner_link?: index == 0}
          end)

        # Prepend A with partner_link?: true
        [%{person: person_a, label: "-", partner_link?: true} | blood_nodes]
    end
  end

  # Same logic as Kinship.path_label — computes what a person at `index` is TO person A
  defp blood_path_label(0, _steps_a, _steps_b, _gender), do: "-"

  defp blood_path_label(index, steps_a, _steps_b, gender) when index <= steps_a do
    Ancestry.Kinship.Label.format(0, index, false, gender)
  end

  defp blood_path_label(index, steps_a, _steps_b, gender) do
    down_steps = index - steps_a

    cond do
      steps_a == 0 -> Ancestry.Kinship.Label.format(down_steps, 0, false, gender)
      true -> Ancestry.Kinship.Label.format(down_steps, steps_a, false, gender)
    end
  end

  # Given two ascending paths that share the same MRCA at the end,
  # produce the full linear path: start -> ... -> mrca -> ... -> end
  defp merge_blood_path(path_ascending, path_descending) do
    descending_tail =
      path_descending
      |> Enum.reverse()
      |> tl()

    path_ascending ++ descending_tail
  end
end
