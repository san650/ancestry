defmodule Ancestry.People.FamilyGraph do
  @moduledoc """
  In-memory index of a family's persons and relationships.
  Built from two queries, enables zero-DB tree/kinship traversal.
  """

  alias Ancestry.People
  alias Ancestry.Relationships
  alias Ancestry.Relationships.Relationship

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
    people = People.list_family_members(family_id)
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

  @doc "Returns [{%Person{}, %Relationship{}}] for active partners (married, relationship)."
  def active_partners(%__MODULE__{} = graph, person_id) do
    graph.partners_by_person
    |> Map.get(person_id, [])
    |> Enum.filter(fn {_p, rel} -> Relationship.active_partner_type?(rel.type) end)
  end

  @doc "Returns [{%Person{}, %Relationship{}}] for former partners (divorced, separated)."
  def former_partners(%__MODULE__{} = graph, person_id) do
    graph.partners_by_person
    |> Map.get(person_id, [])
    |> Enum.filter(fn {_p, rel} -> Relationship.former_partner_type?(rel.type) end)
  end

  @doc "Returns [{%Person{}, %Relationship{}}] — parents of the given child."
  def parents(%__MODULE__{} = graph, child_id) do
    Map.get(graph.parents_by_child, child_id, [])
  end

  @doc "Returns [%Person{}] — all children of the given parent."
  def children(%__MODULE__{} = graph, parent_id) do
    Map.get(graph.children_by_parent, parent_id, [])
  end

  @doc "Returns [%Person{}] — children of pair (both A and B are parents)."
  def children_of_pair(%__MODULE__{} = graph, parent_a_id, parent_b_id) do
    a_children = Map.get(graph.children_by_parent, parent_a_id, [])

    Enum.filter(a_children, fn child ->
      parent_ids =
        graph.parents_by_child
        |> Map.get(child.id, [])
        |> Enum.map(fn {p, _r} -> p.id end)
        |> MapSet.new()

      MapSet.member?(parent_ids, parent_b_id)
    end)
  end

  @doc "Returns [%Person{}] — children where this person is the ONLY parent."
  def solo_children(%__MODULE__{} = graph, person_id) do
    all_children = Map.get(graph.children_by_parent, person_id, [])

    Enum.filter(all_children, fn child ->
      parent_count = length(Map.get(graph.parents_by_child, child.id, []))
      parent_count == 1
    end)
  end

  @doc "Returns true if the person has any children."
  def has_children?(%__MODULE__{} = graph, person_id) do
    Map.get(graph.children_by_parent, person_id, []) != []
  end

  @doc "Fetches a person from the graph. Raises if not found."
  def fetch_person!(%__MODULE__{} = graph, person_id) do
    Map.fetch!(graph.people_by_id, person_id)
  end

  @doc "Returns [{%Person{}, %Relationship{}}] — all partners (active + former)."
  def all_partners(%__MODULE__{} = graph, person_id) do
    Map.get(graph.partners_by_person, person_id, [])
  end

  @doc "Returns %Relationship{} or nil — partner relationship between two people."
  def partner_relationship(%__MODULE__{} = graph, person_a_id, person_b_id) do
    graph.partners_by_person
    |> Map.get(person_a_id, [])
    |> Enum.find_value(fn {p, rel} -> if p.id == person_b_id, do: rel end)
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
