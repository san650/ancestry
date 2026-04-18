defmodule Ancestry.People.FamilyGraph do
  @moduledoc """
  In-memory index of a family's persons and relationships.
  Built from two queries, enables zero-DB tree/kinship traversal.
  """

  alias Ancestry.People
  alias Ancestry.Relationships

  defstruct [
    :family_id,
    :people_by_id,
    :parents_by_child,
    :children_by_parent,
    :partners_by_person
  ]

  @doc """
  Builds the graph from DB — exactly 2 queries.
  """
  def for_family(family_id) do
    people = People.list_people_for_family(family_id)
    relationships = Relationships.list_relationships_for_family(family_id)
    from(people, relationships, family_id)
  end

  @doc """
  Builds the graph from pre-loaded lists (0 queries).
  """
  def from(people, relationships, family_id) do
    people_by_id = Map.new(people, &{&1.id, &1})

    {parents_by_child, children_by_parent, partners_by_person} =
      build_indexes(relationships, people_by_id)

    %__MODULE__{
      family_id: family_id,
      people_by_id: people_by_id,
      parents_by_child: parents_by_child,
      children_by_parent: children_by_parent,
      partners_by_person: partners_by_person
    }
  end

  defp build_indexes(relationships, people_by_id) do
    acc = {%{}, %{}, %{}}

    Enum.reduce(relationships, acc, fn rel, {pbc, cbp, pbp} ->
      person_a = Map.get(people_by_id, rel.person_a_id)
      person_b = Map.get(people_by_id, rel.person_b_id)

      if is_nil(person_a) or is_nil(person_b) do
        {pbc, cbp, pbp}
      else
        case rel.type do
          "parent" ->
            # person_a is parent, person_b is child
            pbc = Map.update(pbc, rel.person_b_id, [{person_a, rel}], &[{person_a, rel} | &1])
            cbp = Map.update(cbp, rel.person_a_id, [person_b], &[person_b | &1])
            {pbc, cbp, pbp}

          type when type in ~w(married relationship divorced separated) ->
            # Bidirectional: index under both endpoints
            pbp =
              pbp
              |> Map.update(rel.person_a_id, [{person_b, rel}], &[{person_b, rel} | &1])
              |> Map.update(rel.person_b_id, [{person_a, rel}], &[{person_a, rel} | &1])

            {pbc, cbp, pbp}

          _ ->
            {pbc, cbp, pbp}
        end
      end
    end)
    |> then(fn {pbc, cbp, pbp} ->
      # Sort children by birth_year ASC NULLS LAST, then id ASC
      cbp =
        Map.new(cbp, fn {parent_id, children} ->
          sorted =
            Enum.sort_by(children, fn p ->
              {is_nil(p.birth_year), p.birth_year || 0, p.id}
            end)

          {parent_id, sorted}
        end)

      {pbc, cbp, pbp}
    end)
  end
end
