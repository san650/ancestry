defmodule Ancestry.Relationships do
  import Ecto.Query

  alias Ancestry.Repo
  alias Ancestry.People.FamilyMember
  alias Ancestry.People.Person
  alias Ancestry.Relationships.Relationship

  def create_relationship(person_a, person_b, type, metadata_attrs \\ %{}) do
    attrs = %{
      person_a_id: person_a.id,
      person_b_id: person_b.id,
      type: type,
      metadata: Map.put(metadata_attrs, :__type__, type)
    }

    with :ok <- validate_not_acquaintance(person_a, person_b),
         :ok <- validate_parent_limit(person_b.id, type),
         :ok <- validate_unique_partner_pair(person_a.id, person_b.id, type) do
      %Relationship{}
      |> Relationship.changeset(attrs)
      |> Repo.insert()
    end
  end

  def update_relationship(%Relationship{} = rel, attrs) do
    rel
    |> Relationship.changeset(attrs)
    |> Repo.update()
  end

  def delete_relationship(%Relationship{} = rel) do
    Repo.delete(rel)
  end

  def count_relationships(person_id) do
    Repo.one(
      from r in Relationship,
        where: r.person_a_id == ^person_id or r.person_b_id == ^person_id,
        select: count(r.id)
    )
  end

  @doc """
  Changes a partner-type relationship to a new partner type, carrying over
  overlapping metadata fields and merging new metadata attributes.
  """
  def update_partner_type(%Relationship{} = rel, new_type, new_metadata_attrs \\ %{}) do
    carried = carry_over_metadata(rel.metadata, new_type)
    merged = Map.merge(carried, new_metadata_attrs)

    attrs = %{
      type: new_type,
      metadata: Map.put(merged, :__type__, new_type)
    }

    rel
    |> Relationship.changeset(attrs)
    |> Repo.update()
  end

  defp carry_over_metadata(nil, _new_type), do: %{}

  defp carry_over_metadata(old_metadata, new_type) do
    target_fields = metadata_fields_for_type(new_type)

    old_metadata
    |> Map.from_struct()
    |> Map.take(target_fields)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp metadata_fields_for_type("married"),
    do: [:marriage_day, :marriage_month, :marriage_year, :marriage_location]

  defp metadata_fields_for_type("relationship"), do: []

  defp metadata_fields_for_type("divorced"),
    do: [
      :marriage_day,
      :marriage_month,
      :marriage_year,
      :marriage_location,
      :divorce_day,
      :divorce_month,
      :divorce_year
    ]

  defp metadata_fields_for_type("separated"),
    do: [
      :marriage_day,
      :marriage_month,
      :marriage_year,
      :marriage_location,
      :separated_day,
      :separated_month,
      :separated_year
    ]

  defp metadata_fields_for_type(_), do: []

  def list_relationships_for_person(person_id) do
    Repo.all(
      from r in Relationship,
        where: r.person_a_id == ^person_id or r.person_b_id == ^person_id
    )
  end

  @doc """
  Returns all relationships where both person_a and person_b are members of the given family.
  """
  def list_relationships_for_family(family_id) do
    from(r in Relationship,
      join: fm_a in FamilyMember,
      on: fm_a.person_id == r.person_a_id and fm_a.family_id == ^family_id,
      join: fm_b in FamilyMember,
      on: fm_b.person_id == r.person_b_id and fm_b.family_id == ^family_id
    )
    |> Repo.all()
  end

  def change_relationship(%Relationship{} = rel, attrs \\ %{}) do
    Relationship.changeset(rel, attrs)
  end

  def get_parents(person_id, opts \\ []) do
    query =
      from(r in Relationship,
        join: p in Person,
        on: p.id == r.person_a_id,
        where: r.person_b_id == ^person_id and r.type == "parent",
        select: {p, r}
      )

    query = maybe_filter_by_family(query, opts[:family_id])
    Repo.all(query)
  end

  def get_children(person_id, opts \\ []) do
    query =
      from(r in Relationship,
        join: p in Person,
        on: p.id == r.person_b_id,
        where: r.person_a_id == ^person_id and r.type == "parent",
        order_by: [asc_nulls_last: p.birth_year, asc: p.id],
        select: p
      )

    query = maybe_filter_by_family(query, opts[:family_id])
    Repo.all(query)
  end

  def get_children_with_coparents(person_id) do
    from(child in Person,
      join: r1 in Relationship,
      on: r1.person_b_id == child.id and r1.person_a_id == ^person_id and r1.type == "parent",
      left_join: r2 in Relationship,
      on: r2.person_b_id == child.id and r2.type == "parent" and r2.person_a_id != ^person_id,
      left_join: coparent in Person,
      on: coparent.id == r2.person_a_id,
      select: {child, coparent}
    )
    |> Repo.all()
  end

  @doc """
  Returns list of `{person, relationship}` tuples for active partners (married, relationship).
  """
  def get_active_partners(person_id, opts \\ []) do
    get_relationship_partners(person_id, Relationship.active_partner_types(), opts)
  end

  @doc """
  Returns list of `{person, relationship}` tuples for former partners (divorced, separated).
  """
  def get_former_partners(person_id, opts \\ []) do
    get_relationship_partners(person_id, Relationship.former_partner_types(), opts)
  end

  @doc """
  Returns list of `{person, relationship}` tuples for all partners (active + former).
  """
  def get_all_partners(person_id) do
    get_relationship_partners(person_id, Relationship.partner_types(), [])
  end

  @doc """
  Returns the partner-type relationship between two people (any partner type), or nil.
  """
  def get_partner_relationship(person_a_id, person_b_id) do
    {a, b} =
      if person_a_id < person_b_id,
        do: {person_a_id, person_b_id},
        else: {person_b_id, person_a_id}

    types = Relationship.partner_types()

    Repo.one(
      from r in Relationship,
        where: r.person_a_id == ^a and r.person_b_id == ^b and r.type in ^types
    )
  end

  defp get_relationship_partners(person_id, types, opts) do
    family_id = opts[:family_id]

    query =
      from(r in Relationship,
        join: p in Person,
        on:
          (r.person_a_id == ^person_id and p.id == r.person_b_id) or
            (r.person_b_id == ^person_id and p.id == r.person_a_id),
        where: r.type in ^types,
        select: {p, r}
      )

    query = maybe_filter_by_family(query, family_id)
    Repo.all(query)
  end

  def get_children_of_pair(parent_a_id, parent_b_id, opts \\ []) do
    query =
      from(p in Person,
        join: r1 in Relationship,
        on: r1.person_b_id == p.id and r1.person_a_id == ^parent_a_id and r1.type == "parent",
        join: r2 in Relationship,
        on: r2.person_b_id == p.id and r2.person_a_id == ^parent_b_id and r2.type == "parent",
        order_by: [asc_nulls_last: p.birth_year, asc: p.id],
        select: p
      )

    query = maybe_filter_person_by_family(query, opts[:family_id])
    Repo.all(query)
  end

  def get_solo_children(person_id, opts \\ []) do
    query =
      from(p in Person,
        join: r in Relationship,
        on: r.person_b_id == p.id and r.person_a_id == ^person_id and r.type == "parent",
        left_join: r2 in Relationship,
        on: r2.person_b_id == p.id and r2.type == "parent" and r2.person_a_id != ^person_id,
        where: is_nil(r2.id),
        order_by: [asc_nulls_last: p.birth_year, asc: p.id],
        select: p
      )

    query = maybe_filter_person_by_family(query, opts[:family_id])
    Repo.all(query)
  end

  @doc """
  Returns siblings inferred from shared parents. Returns a mixed list:
  - `{person, parent_a_id, parent_b_id}` for full siblings (share both parents)
  - `{person, shared_parent_id}` for half-siblings (share one parent)
  """
  def get_siblings(person_id) do
    parent_ids =
      from(r in Relationship,
        where: r.person_b_id == ^person_id and r.type == "parent",
        select: r.person_a_id
      )
      |> Repo.all()

    case parent_ids do
      [] ->
        []

      [single_parent_id] ->
        from(p in Person,
          join: r in Relationship,
          on: r.person_b_id == p.id and r.person_a_id == ^single_parent_id and r.type == "parent",
          where: p.id != ^person_id,
          select: p
        )
        |> Repo.all()
        |> Enum.map(fn person -> {person, single_parent_id} end)

      [parent1_id, parent2_id] ->
        sibling_candidates =
          from(p in Person,
            join: r in Relationship,
            on: r.person_b_id == p.id and r.type == "parent",
            where: r.person_a_id in ^parent_ids and p.id != ^person_id,
            group_by: p.id,
            select: {p, fragment("array_agg(?)", r.person_a_id)}
          )
          |> Repo.all()

        both_parents = MapSet.new([parent1_id, parent2_id])

        Enum.map(sibling_candidates, fn {person, shared_ids} ->
          shared_set = MapSet.new(shared_ids)

          if MapSet.equal?(shared_set, both_parents) do
            [pa, pb] = Enum.sort([parent1_id, parent2_id])
            {person, pa, pb}
          else
            shared_parent_id = shared_ids |> Enum.find(&(&1 in parent_ids))
            {person, shared_parent_id}
          end
        end)
    end
  end

  defp maybe_filter_by_family(query, nil), do: query

  defp maybe_filter_by_family(query, family_id) do
    from [_r, p] in query,
      join: fm in FamilyMember,
      on: fm.person_id == p.id and fm.family_id == ^family_id
  end

  defp maybe_filter_person_by_family(query, nil), do: query

  defp maybe_filter_person_by_family(query, family_id) do
    from [p, ...] in query,
      join: fm in FamilyMember,
      on: fm.person_id == p.id and fm.family_id == ^family_id
  end

  defp validate_not_acquaintance(person_a, person_b) do
    if Person.acquaintance?(person_a) or Person.acquaintance?(person_b) do
      {:error, :acquaintance_cannot_have_relationships}
    else
      :ok
    end
  end

  defp validate_parent_limit(child_id, "parent") do
    count =
      Repo.aggregate(
        from(r in Relationship, where: r.person_b_id == ^child_id and r.type == "parent"),
        :count
      )

    if count >= 2, do: {:error, :max_parents_reached}, else: :ok
  end

  defp validate_parent_limit(_child_id, _type), do: :ok

  defp validate_unique_partner_pair(person_a_id, person_b_id, type) do
    if Relationship.partner_type?(type) do
      {a, b} =
        if person_a_id < person_b_id,
          do: {person_a_id, person_b_id},
          else: {person_b_id, person_a_id}

      partner_types = Relationship.partner_types()

      exists? =
        Repo.exists?(
          from r in Relationship,
            where: r.person_a_id == ^a and r.person_b_id == ^b and r.type in ^partner_types
        )

      if exists?, do: {:error, :partner_relationship_exists}, else: :ok
    else
      :ok
    end
  end
end
