defmodule Ancestry.People do
  import Ecto.Query

  alias Ancestry.Repo
  alias Ancestry.People.FamilyMember
  alias Ancestry.People.Person
  alias Ancestry.Relationships.Relationship
  alias Ancestry.StringUtils

  def list_birthdays_for_family(family_id) do
    Repo.all(
      from p in Person,
        join: fm in FamilyMember,
        on: fm.person_id == p.id and fm.family_id == ^family_id,
        where: not is_nil(p.birth_month) and not is_nil(p.birth_day),
        where:
          fragment(
            """
            ? <= CASE ?
              WHEN 1 THEN 31 WHEN 2 THEN 29 WHEN 3 THEN 31 WHEN 4 THEN 30
              WHEN 5 THEN 31 WHEN 6 THEN 30 WHEN 7 THEN 31 WHEN 8 THEN 31
              WHEN 9 THEN 30 WHEN 10 THEN 31 WHEN 11 THEN 30 WHEN 12 THEN 31
            END
            """,
            p.birth_day,
            p.birth_month
          ),
        order_by: [asc: p.birth_month, asc: p.birth_day]
    )
  end

  def list_people(family_id) do
    Repo.all(
      from p in Person,
        join: fm in FamilyMember,
        on: fm.person_id == p.id,
        where: fm.family_id == ^family_id,
        order_by: [asc: p.surname, asc: p.given_name]
    )
  end

  def list_family_members(family_id) do
    Repo.all(
      from p in Person,
        join: fm in FamilyMember,
        on: fm.person_id == p.id,
        where: fm.family_id == ^family_id,
        where: p.kind == "family_member",
        order_by: [asc: p.surname, asc: p.given_name]
    )
  end

  def list_people_for_family_with_relationship_counts(family_id) do
    list_people_for_family_with_relationship_counts(family_id, "", [])
  end

  def list_people_for_family_with_relationship_counts(family_id, opts) when is_list(opts) do
    unlinked_only = Keyword.get(opts, :unlinked_only, false)
    acquaintance_only = Keyword.get(opts, :acquaintance_only, false)

    base_people_query(family_id)
    |> maybe_filter_unlinked(unlinked_only)
    |> maybe_filter_acquaintance_only(acquaintance_only)
    |> Repo.all()
  end

  def list_people_for_family_with_relationship_counts(family_id, search_term)
      when is_binary(search_term) do
    list_people_for_family_with_relationship_counts(family_id, search_term, [])
  end

  def list_people_for_family_with_relationship_counts(family_id, "", opts),
    do: list_people_for_family_with_relationship_counts(family_id, opts)

  def list_people_for_family_with_relationship_counts(family_id, search_term, opts) do
    unlinked_only = Keyword.get(opts, :unlinked_only, false)
    acquaintance_only = Keyword.get(opts, :acquaintance_only, false)

    like = StringUtils.normalize_sql_search(search_term)

    base_people_query(family_id)
    |> where([p], ilike(p.name_search, ^like))
    |> maybe_filter_unlinked(unlinked_only)
    |> maybe_filter_acquaintance_only(acquaintance_only)
    |> Repo.all()
  end

  def list_people_for_org(org_id) do
    base_org_people_query(org_id)
    |> Repo.all()
  end

  def list_people_for_org(org_id, opts) when is_list(opts) do
    no_family_only = Keyword.get(opts, :no_family_only, false)
    acquaintance_only = Keyword.get(opts, :acquaintance_only, false)

    base_org_people_query(org_id)
    |> maybe_filter_no_family(no_family_only)
    |> maybe_filter_acquaintance_only(acquaintance_only)
    |> Repo.all()
  end

  def list_people_for_org(org_id, search_term) when is_binary(search_term) do
    list_people_for_org(org_id, search_term, [])
  end

  def list_people_for_org(org_id, "", opts), do: list_people_for_org(org_id, opts)

  def list_people_for_org(org_id, search_term, opts) do
    no_family_only = Keyword.get(opts, :no_family_only, false)
    acquaintance_only = Keyword.get(opts, :acquaintance_only, false)

    like = StringUtils.normalize_sql_search(search_term)

    base_org_people_query(org_id)
    |> where([p], ilike(p.name_search, ^like))
    |> maybe_filter_no_family(no_family_only)
    |> maybe_filter_acquaintance_only(acquaintance_only)
    |> Repo.all()
  end

  defp base_org_people_query(org_id) do
    from p in Person,
      where: p.organization_id == ^org_id,
      left_join: r in Relationship,
      on: r.person_a_id == p.id or r.person_b_id == p.id,
      group_by: p.id,
      order_by: [asc: p.surname, asc: p.given_name],
      select: {p, count(r.id, :distinct)}
  end

  defp maybe_filter_no_family(query, true) do
    query
    |> join(:left, [p], fm in FamilyMember, on: fm.person_id == p.id, as: :fm_no_family)
    |> having([fm_no_family: fm], fragment("COUNT(DISTINCT ?) = 0", fm.family_id))
  end

  defp maybe_filter_no_family(query, false), do: query

  def get_person!(id), do: Repo.get!(Person, id) |> Repo.preload(:families)

  def create_person(family, attrs) do
    Repo.transaction(fn ->
      case %Person{organization_id: family.organization_id}
           |> Person.changeset(attrs)
           |> Repo.insert() do
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

  def delete_people(person_ids) do
    Repo.transaction(fn ->
      for id <- person_ids do
        person = get_person!(id)
        {:ok, _} = delete_person(person)
      end
    end)
  end

  def add_to_family(%Person{} = person, family) do
    if person.organization_id != family.organization_id do
      {:error, :organization_mismatch}
    else
      %FamilyMember{family_id: family.id, person_id: person.id}
      |> FamilyMember.changeset(%{})
      |> Repo.insert()
    end
  end

  @doc """
  Idempotently ensures a person is a member of the given family.

  Returns:
  - `{:ok, :added}` — link was newly created
  - `{:ok, :already_linked}` — link already existed (no-op)
  - `{:error, reason}` — real error (e.g., `:organization_mismatch` or `:link_failed`)
  """
  def link_person_to_family(%Person{} = person, family) do
    case add_to_family(person, family) do
      {:ok, _} ->
        {:ok, :added}

      {:error, %Ecto.Changeset{errors: errors}} ->
        if Enum.any?(errors, fn {_k, {msg, _}} -> msg =~ "already" end) do
          {:ok, :already_linked}
        else
          {:error, :link_failed}
        end

      {:error, reason} ->
        {:error, reason}
    end
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

  def search_people(query, exclude_family_id, org_id) do
    like = StringUtils.normalize_sql_search(query)

    Repo.all(
      from p in Person,
        left_join: fm in FamilyMember,
        on: fm.person_id == p.id and fm.family_id == ^exclude_family_id,
        where: is_nil(fm.id),
        where: p.organization_id == ^org_id,
        where: ilike(p.name_search, ^like),
        order_by: [asc: p.surname, asc: p.given_name],
        limit: 20,
        preload: [:families]
    )
  end

  def search_all_people(query, org_id) do
    like = StringUtils.normalize_sql_search(query)

    Repo.all(
      from p in Person,
        where: p.organization_id == ^org_id,
        where: ilike(p.name_search, ^like),
        order_by: [asc: p.surname, asc: p.given_name],
        limit: 20,
        preload: [:families]
    )
  end

  def search_all_people(query, exclude_person_id, org_id) do
    like = StringUtils.normalize_sql_search(query)

    Repo.all(
      from p in Person,
        where: p.id != ^exclude_person_id,
        where: p.organization_id == ^org_id,
        where: ilike(p.name_search, ^like),
        order_by: [asc: p.surname, asc: p.given_name],
        limit: 20,
        preload: [:families]
    )
  end

  def search_family_members(query, family_id, exclude_person_id) do
    like = StringUtils.normalize_sql_search(query)

    Repo.all(
      from p in Person,
        join: fm in FamilyMember,
        on: fm.person_id == p.id,
        where: fm.family_id == ^family_id,
        where: p.id != ^exclude_person_id,
        where: p.kind == "family_member",
        where: ilike(p.name_search, ^like),
        order_by: [asc: p.surname, asc: p.given_name],
        limit: 20
    )
  end

  def create_person_without_family(org, attrs) do
    %Person{organization_id: org.id}
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
    person = Repo.get!(Person, person_id)

    if Person.acquaintance?(person) do
      {:error, :acquaintance_cannot_be_default}
    else
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
  end

  def clear_default_member(family_id) do
    Repo.update_all(
      from(fm in FamilyMember, where: fm.family_id == ^family_id),
      set: [is_default: false]
    )

    :ok
  end

  def convert_to_acquaintance(%Person{} = person) do
    alias Ecto.Multi

    person = Repo.preload(person, :families)

    Multi.new()
    |> Multi.update(:person, Ecto.Changeset.change(person, %{kind: "acquaintance"}))
    |> Multi.run(:clear_defaults, &clear_default_memberships(&1, &2, person))
    |> Repo.transaction()
    |> case do
      {:ok, %{person: person}} -> {:ok, person}
      {:error, _op, changeset, _} -> {:error, changeset}
    end
  end

  defp clear_default_memberships(_repo, _changes, person) do
    for family <- person.families do
      Repo.update_all(
        from(fm in FamilyMember,
          where:
            fm.family_id == ^family.id and fm.person_id == ^person.id and fm.is_default == true
        ),
        set: [is_default: false]
      )
    end

    {:ok, :cleared}
  end

  def convert_to_family_member(%Person{} = person) do
    person
    |> Ecto.Changeset.change(%{kind: "family_member"})
    |> Repo.update()
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

  defp base_people_query(family_id) do
    from p in Person,
      join: fm in FamilyMember,
      on: fm.person_id == p.id and fm.family_id == ^family_id,
      left_join: r in Relationship,
      as: :rel,
      on: r.person_a_id == p.id or r.person_b_id == p.id,
      left_join: fm_other in FamilyMember,
      as: :fm_other,
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
  end

  defp maybe_filter_unlinked(query, true) do
    having(
      query,
      [rel: r, fm_other: fm_other],
      fragment(
        "COUNT(DISTINCT CASE WHEN ? IS NOT NULL THEN ? END) = 0",
        fm_other.id,
        r.id
      )
    )
  end

  defp maybe_filter_unlinked(query, false), do: query

  defp maybe_filter_acquaintance_only(query, true) do
    where(query, [p], p.kind == "acquaintance")
  end

  defp maybe_filter_acquaintance_only(query, false), do: query
end
