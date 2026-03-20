defmodule Ancestry.People do
  import Ecto.Query

  alias Ancestry.Repo
  alias Ancestry.People.FamilyMember
  alias Ancestry.People.Person
  alias Ancestry.Relationships.Relationship

  def list_people_for_family(family_id) do
    Repo.all(
      from p in Person,
        join: fm in FamilyMember,
        on: fm.person_id == p.id,
        where: fm.family_id == ^family_id,
        order_by: [asc: p.surname, asc: p.given_name]
    )
  end

  def list_people_for_family_with_relationship_counts(family_id) do
    list_people_for_family_with_relationship_counts(family_id, "", [])
  end

  def list_people_for_family_with_relationship_counts(family_id, "") do
    list_people_for_family_with_relationship_counts(family_id, "", [])
  end

  def list_people_for_family_with_relationship_counts(family_id, search_term) do
    list_people_for_family_with_relationship_counts(family_id, search_term, [])
  end

  def list_people_for_family_with_relationship_counts(family_id, "", opts) do
    unlinked_only = Keyword.get(opts, :unlinked_only, false)

    query =
      from p in Person,
        join: fm in FamilyMember,
        on: fm.person_id == p.id and fm.family_id == ^family_id,
        left_join: r in Relationship,
        on: r.person_a_id == p.id or r.person_b_id == p.id,
        left_join: fm_other in FamilyMember,
        on:
          fm_other.family_id == ^family_id and
            ((r.person_a_id == p.id and fm_other.person_id == r.person_b_id) or
               (r.person_b_id == p.id and fm_other.person_id == r.person_a_id)),
        group_by: p.id,
        order_by: [asc: p.surname, asc: p.given_name],
        select:
          {p,
           fragment(
             "COUNT(DISTINCT CASE WHEN ? IS NOT NULL THEN ? END)",
             fm_other.id,
             r.id
           )}

    query =
      if unlinked_only do
        where(query, [p, fm, r, fm_other], count(fm_other.id) == 0)
      else
        query
      end

    Repo.all(query)
  end

  def list_people_for_family_with_relationship_counts(family_id, search_term, opts) do
    escaped =
      search_term
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    like = "%#{escaped}%"
    unlinked_only = Keyword.get(opts, :unlinked_only, false)

    query =
      from p in Person,
        join: fm in FamilyMember,
        on: fm.person_id == p.id and fm.family_id == ^family_id,
        left_join: r in Relationship,
        on: r.person_a_id == p.id or r.person_b_id == p.id,
        left_join: fm_other in FamilyMember,
        on:
          fm_other.family_id == ^family_id and
            ((r.person_a_id == p.id and fm_other.person_id == r.person_b_id) or
               (r.person_b_id == p.id and fm_other.person_id == r.person_a_id)),
        where:
          fragment("unaccent(?) ILIKE unaccent(?)", p.given_name, ^like) or
            fragment("unaccent(?) ILIKE unaccent(?)", p.surname, ^like) or
            fragment("unaccent(?) ILIKE unaccent(?)", p.nickname, ^like),
        group_by: p.id,
        order_by: [asc: p.surname, asc: p.given_name],
        select:
          {p,
           fragment(
             "COUNT(DISTINCT CASE WHEN ? IS NOT NULL THEN ? END)",
             fm_other.id,
             r.id
           )}

    query =
      if unlinked_only do
        where(query, [p, fm, r, fm_other], count(fm_other.id) == 0)
      else
        query
      end

    Repo.all(query)
  end

  def get_person!(id), do: Repo.get!(Person, id) |> Repo.preload(:families)

  def create_person(family, attrs) do
    Repo.transaction(fn ->
      case %Person{} |> Person.changeset(attrs) |> Repo.insert() do
        {:ok, person} ->
          %FamilyMember{family_id: family.id, person_id: person.id}
          |> FamilyMember.changeset(%{})
          |> Repo.insert!()

          person

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  def update_person(%Person{} = person, attrs) do
    person
    |> Person.changeset(attrs)
    |> Repo.update()
  end

  def delete_person(%Person{} = person) do
    cleanup_person_files(person)
    Repo.delete(person)
  end

  def add_to_family(%Person{} = person, family) do
    %FamilyMember{family_id: family.id, person_id: person.id}
    |> FamilyMember.changeset(%{})
    |> Repo.insert()
  end

  def remove_from_family(%Person{} = person, family) do
    Repo.delete_all(
      from fm in FamilyMember,
        where: fm.family_id == ^family.id and fm.person_id == ^person.id
    )
    |> case do
      {1, _} -> {:ok, person}
      {0, _} -> {:error, :not_found}
    end
  end

  def search_people(query, exclude_family_id) do
    escaped =
      query
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    like = "%#{escaped}%"

    Repo.all(
      from p in Person,
        left_join: fm in FamilyMember,
        on: fm.person_id == p.id and fm.family_id == ^exclude_family_id,
        where: is_nil(fm.id),
        where:
          fragment("unaccent(?) ILIKE unaccent(?)", p.given_name, ^like) or
            fragment("unaccent(?) ILIKE unaccent(?)", p.surname, ^like) or
            fragment("unaccent(?) ILIKE unaccent(?)", p.nickname, ^like) or
            fragment(
              "EXISTS (SELECT 1 FROM unnest(?) AS name WHERE unaccent(name) ILIKE unaccent(?))",
              p.alternate_names,
              ^like
            ),
        order_by: [asc: p.surname, asc: p.given_name],
        limit: 20,
        preload: [:families]
    )
  end

  def search_all_people(query) do
    escaped =
      query
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    like = "%#{escaped}%"

    Repo.all(
      from p in Person,
        where:
          fragment("unaccent(?) ILIKE unaccent(?)", p.given_name, ^like) or
            fragment("unaccent(?) ILIKE unaccent(?)", p.surname, ^like) or
            fragment("unaccent(?) ILIKE unaccent(?)", p.nickname, ^like) or
            fragment(
              "EXISTS (SELECT 1 FROM unnest(?) AS name WHERE unaccent(name) ILIKE unaccent(?))",
              p.alternate_names,
              ^like
            ),
        order_by: [asc: p.surname, asc: p.given_name],
        limit: 20,
        preload: [:families]
    )
  end

  def search_all_people(query, exclude_person_id) do
    escaped =
      query
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    like = "%#{escaped}%"

    Repo.all(
      from p in Person,
        where: p.id != ^exclude_person_id,
        where:
          fragment("unaccent(?) ILIKE unaccent(?)", p.given_name, ^like) or
            fragment("unaccent(?) ILIKE unaccent(?)", p.surname, ^like) or
            fragment("unaccent(?) ILIKE unaccent(?)", p.nickname, ^like) or
            fragment(
              "EXISTS (SELECT 1 FROM unnest(?) AS name WHERE unaccent(name) ILIKE unaccent(?))",
              p.alternate_names,
              ^like
            ),
        order_by: [asc: p.surname, asc: p.given_name],
        limit: 20,
        preload: [:families]
    )
  end

  def search_family_members(query, family_id, exclude_person_id) do
    escaped =
      query
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    like = "%#{escaped}%"

    Repo.all(
      from p in Person,
        join: fm in FamilyMember,
        on: fm.person_id == p.id,
        where: fm.family_id == ^family_id,
        where: p.id != ^exclude_person_id,
        where:
          fragment("unaccent(?) ILIKE unaccent(?)", p.given_name, ^like) or
            fragment("unaccent(?) ILIKE unaccent(?)", p.surname, ^like) or
            fragment("unaccent(?) ILIKE unaccent(?)", p.nickname, ^like),
        order_by: [asc: p.surname, asc: p.given_name],
        limit: 20
    )
  end

  def create_person_without_family(attrs) do
    %Person{}
    |> Person.changeset(attrs)
    |> Repo.insert()
  end

  def get_default_person(family_id) do
    Repo.one(
      from p in Person,
        join: fm in FamilyMember,
        on: fm.person_id == p.id,
        where: fm.family_id == ^family_id and fm.is_default == true
    )
  end

  def set_default_member(family_id, person_id) do
    Repo.transaction(fn ->
      Repo.update_all(
        from(fm in FamilyMember, where: fm.family_id == ^family_id),
        set: [is_default: false]
      )

      {1, _} =
        Repo.update_all(
          from(fm in FamilyMember,
            where: fm.family_id == ^family_id and fm.person_id == ^person_id
          ),
          set: [is_default: true]
        )
    end)
  end

  def clear_default_member(family_id) do
    Repo.update_all(
      from(fm in FamilyMember, where: fm.family_id == ^family_id),
      set: [is_default: false]
    )

    :ok
  end

  def change_person(%Person{} = person, attrs \\ %{}) do
    Person.changeset(person, attrs)
  end

  def update_photo_pending(%Person{} = person, original_path) do
    person
    |> Ecto.Changeset.change(%{photo_status: "pending"})
    |> Repo.update!()

    Oban.insert(
      Ancestry.Workers.ProcessPersonPhotoJob.new(%{
        person_id: person.id,
        original_path: original_path
      })
    )
  end

  def update_photo_processed(%Person{} = person, filename) do
    person
    |> Ecto.Changeset.change(%{
      photo: %{file_name: filename, updated_at: nil},
      photo_status: "processed"
    })
    |> Repo.update()
  end

  def update_photo_failed(%Person{} = person) do
    person
    |> Ecto.Changeset.change(%{photo_status: "failed"})
    |> Repo.update()
  end

  def remove_photo(%Person{} = person) do
    result =
      person
      |> Ecto.Changeset.change(%{photo: nil, photo_status: nil})
      |> Repo.update()

    case result do
      {:ok, person} ->
        cleanup_person_files(person)
        {:ok, person}

      error ->
        error
    end
  end

  defp cleanup_person_files(person) do
    photo_dir = Path.join(["priv", "static", "uploads", "people", "#{person.id}"])
    File.rm_rf(photo_dir)
  end
end
