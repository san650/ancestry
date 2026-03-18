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

    with :ok <- validate_parent_limit(person_b.id, type) do
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

  def convert_to_ex_partner(%Relationship{type: "partner"} = rel, divorce_attrs) do
    ex_metadata =
      %{
        __type__: "ex_partner",
        marriage_day: rel.metadata.marriage_day,
        marriage_month: rel.metadata.marriage_month,
        marriage_year: rel.metadata.marriage_year,
        marriage_location: rel.metadata.marriage_location
      }
      |> Map.merge(divorce_attrs)

    Repo.transaction(fn ->
      case Repo.delete(rel) do
        {:ok, _} ->
          %Relationship{}
          |> Relationship.changeset(%{
            person_a_id: rel.person_a_id,
            person_b_id: rel.person_b_id,
            type: "ex_partner",
            metadata: ex_metadata
          })
          |> Repo.insert()
          |> case do
            {:ok, ex_rel} -> ex_rel
            {:error, changeset} -> Repo.rollback(changeset)
          end

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

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

  @doc """
  Returns list of `{person, relationship}` tuples where person is a parent of the given person_id.
  """
  def get_parents(person_id) do
    from(r in Relationship,
      join: p in Person,
      on: p.id == r.person_a_id,
      where: r.person_b_id == ^person_id and r.type == "parent",
      select: {p, r}
    )
    |> Repo.all()
  end

  @doc """
  Returns list of persons who are children of the given person_id.
  """
  def get_children(person_id) do
    from(r in Relationship,
      join: p in Person,
      on: p.id == r.person_b_id,
      where: r.person_a_id == ^person_id and r.type == "parent",
      select: p
    )
    |> Repo.all()
  end

  @doc """
  Returns all children of person_id with their co-parent (if any).
  Returns `[{child, coparent | nil}]`.
  """
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
  Returns list of `{person, relationship}` tuples for current partners of the given person_id.
  """
  def get_partners(person_id) do
    get_relationship_partners(person_id, "partner")
  end

  @doc """
  Returns list of `{person, relationship}` tuples for ex-partners of the given person_id.
  """
  def get_ex_partners(person_id) do
    get_relationship_partners(person_id, "ex_partner")
  end

  defp get_relationship_partners(person_id, type) do
    as_a =
      from(r in Relationship,
        join: p in Person,
        on: p.id == r.person_b_id,
        where: r.person_a_id == ^person_id and r.type == ^type,
        select: {p, r}
      )

    as_b =
      from(r in Relationship,
        join: p in Person,
        on: p.id == r.person_a_id,
        where: r.person_b_id == ^person_id and r.type == ^type,
        select: {p, r}
      )

    Repo.all(as_a) ++ Repo.all(as_b)
  end

  @doc """
  Returns list of persons who have BOTH parent_a and parent_b as parents.
  """
  def get_children_of_pair(parent_a_id, parent_b_id) do
    from(p in Person,
      join: r1 in Relationship,
      on: r1.person_b_id == p.id and r1.person_a_id == ^parent_a_id and r1.type == "parent",
      join: r2 in Relationship,
      on: r2.person_b_id == p.id and r2.person_a_id == ^parent_b_id and r2.type == "parent",
      select: p
    )
    |> Repo.all()
  end

  @doc """
  Returns list of persons who are children of person_id but do NOT have a second parent.
  """
  def get_solo_children(person_id) do
    from(p in Person,
      join: r in Relationship,
      on: r.person_b_id == p.id and r.person_a_id == ^person_id and r.type == "parent",
      left_join: r2 in Relationship,
      on: r2.person_b_id == p.id and r2.type == "parent" and r2.person_a_id != ^person_id,
      where: is_nil(r2.id),
      select: p
    )
    |> Repo.all()
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

  defp validate_parent_limit(child_id, "parent") do
    count =
      Repo.aggregate(
        from(r in Relationship, where: r.person_b_id == ^child_id and r.type == "parent"),
        :count
      )

    if count >= 2, do: {:error, :max_parents_reached}, else: :ok
  end

  defp validate_parent_limit(_child_id, _type), do: :ok
end
