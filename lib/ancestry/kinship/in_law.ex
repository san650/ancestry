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
        path = build_in_law_path(path_ids, person_a, person_b, partner_person, side)

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
  # For side :a — A is prepended before the blood path (partner → B)
  #   path_ids = {person_a_id, path_partner_to_mrca, path_b_to_mrca}
  #   final path: [A, partner, ..blood nodes..., B]
  #   A and partner are marked partner_link?: true
  #
  # For side :b — B is appended after the blood path (A → partner)
  #   path_ids = {path_a_to_mrca, path_partner_to_mrca, person_b_id}
  #   final path: [A, ..blood nodes..., partner, B]
  #   partner and B are marked partner_link?: true
  defp build_in_law_path(path_ids, person_a, person_b, partner_person, side) do
    case side do
      :a ->
        {_a_id, path_partner, path_b} = path_ids
        blood_ids = blood_path_ids(path_partner, path_b)

        # blood_ids[0] = partner (start), blood_ids[-1] = B
        blood_nodes =
          Enum.with_index(blood_ids)
          |> Enum.map(fn {id, idx} ->
            person = People.get_person!(id)
            # index 0 is the partner itself — label it "-" like the start node
            label = if idx == 0, do: "-", else: "#{idx}"
            %{person: person, label: label, partner_link?: false}
          end)

        partner_node = %{person: partner_person, label: "-", partner_link?: true}
        # Replace the first blood node (which is the partner) with the partner_link? version
        [_first | rest_blood] = blood_nodes

        [
          %{person: person_a, label: "-", partner_link?: true},
          partner_node
          | rest_blood
        ]

      :b ->
        {path_a, path_partner, _b_id} = path_ids
        blood_ids = blood_path_ids(path_a, path_partner)

        # blood_ids[0] = A (start), blood_ids[-1] = B's partner
        blood_nodes =
          Enum.with_index(blood_ids)
          |> Enum.map(fn {id, idx} ->
            person = People.get_person!(id)
            label = if idx == 0, do: "-", else: "#{idx}"
            %{person: person, label: label, partner_link?: false}
          end)

        # Replace the last blood node (B's partner) with partner_link?: true
        {all_but_last, [last_blood]} = Enum.split(blood_nodes, length(blood_nodes) - 1)
        partner_node = %{last_blood | partner_link?: true}

        all_but_last ++
          [
            partner_node,
            %{person: person_b, label: "-", partner_link?: true}
          ]
    end
  end

  # Given path_from_start (ascending) and path_to_end (ascending, ends at same MRCA),
  # produce the full linear path IDs: start -> ... -> mrca -> ... -> end
  defp blood_path_ids(path_ascending, path_descending) do
    # path_ascending: [start_id, ..., mrca_id]
    # path_descending: [end_id, ..., mrca_id]
    # We want: path_ascending ++ reverse(tail of path_descending)
    descending_tail =
      path_descending
      |> Enum.reverse()
      |> tl()

    path_ascending ++ descending_tail
  end
end
