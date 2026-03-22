defmodule Ancestry.Families do
  import Ecto.Query
  alias Ancestry.Repo
  alias Ancestry.Families.Family
  alias Ancestry.People
  alias Ancestry.People.Person
  alias Ancestry.People.FamilyMember

  def list_families(org_id) do
    Repo.all(from f in Family, where: f.organization_id == ^org_id, order_by: [asc: f.name])
  end

  def get_family!(id), do: Repo.get!(Family, id)

  def create_family(%Ancestry.Organizations.Organization{} = org, attrs) do
    %Family{organization_id: org.id}
    |> Family.changeset(attrs)
    |> Repo.insert()
  end

  def update_family(%Family{} = family, attrs) do
    family
    |> Family.changeset(attrs)
    |> Repo.update()
  end

  def delete_family(%Family{} = family) do
    cleanup_family_files(family)
    Repo.delete(family)
  end

  def change_family(%Family{} = family, attrs \\ %{}) do
    Family.changeset(family, attrs)
  end

  def update_cover_pending(%Family{} = family, original_path) do
    family
    |> Ecto.Changeset.change(%{cover_status: "pending"})
    |> Repo.update!()

    Oban.insert(
      Ancestry.Workers.ProcessFamilyCoverJob.new(%{
        family_id: family.id,
        original_path: original_path
      })
    )
  end

  def update_cover_processed(%Family{} = family, filename) do
    family
    |> Ecto.Changeset.change(%{
      cover: %{file_name: filename, updated_at: nil},
      cover_status: "processed"
    })
    |> Repo.update()
  end

  def update_cover_failed(%Family{} = family) do
    family
    |> Ecto.Changeset.change(%{cover_status: "failed"})
    |> Repo.update()
  end

  @doc """
  Creates a new family from a person by traversing all connected relationships
  in the source family via BFS and bulk-inserting family members.

  The selected person is set as the default member of the new family.

  ## Options

    * `:include_partner_ancestors` - when `true`, includes the parents of
      partners discovered during traversal. Defaults to `false`.
  """
  def create_family_from_person(
        %Ancestry.Organizations.Organization{} = org,
        family_name,
        %Person{} = person,
        source_family_id,
        opts \\ []
      ) do
    Repo.transaction(fn ->
      case create_family(org, %{name: family_name}) do
        {:ok, new_family} ->
          person_ids = collect_connected_people(person.id, source_family_id, opts)

          now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

          members =
            Enum.map(person_ids, fn pid ->
              %{family_id: new_family.id, person_id: pid, inserted_at: now, updated_at: now}
            end)

          Repo.insert_all(FamilyMember, members)

          People.set_default_member(new_family.id, person.id)

          new_family

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp collect_connected_people(person_id, source_family_id, opts) do
    include_partner_ancestors = Keyword.get(opts, :include_partner_ancestors, false)
    family_opts = [family_id: source_family_id]

    ancestors = collect_ancestors(person_id, MapSet.new(), family_opts)
    descendants = collect_descendants(person_id, MapSet.new(), family_opts)

    partners =
      (Ancestry.Relationships.get_active_partners(person_id, family_opts) ++
         Ancestry.Relationships.get_former_partners(person_id, family_opts))
      |> Enum.map(fn {person, _rel} -> person.id end)

    partner_ancestors =
      if include_partner_ancestors do
        Enum.reduce(partners, MapSet.new(), fn partner_id, acc ->
          collect_ancestors(partner_id, acc, family_opts)
        end)
      else
        MapSet.new()
      end

    MapSet.new([person_id])
    |> MapSet.union(ancestors)
    |> MapSet.union(descendants)
    |> MapSet.union(MapSet.new(partners))
    |> MapSet.union(partner_ancestors)
  end

  defp collect_ancestors(person_id, visited, opts) do
    if MapSet.member?(visited, person_id) do
      visited
    else
      parents =
        Ancestry.Relationships.get_parents(person_id, opts)
        |> Enum.map(fn {person, _rel} -> person.id end)

      visited = Enum.reduce(parents, visited, &MapSet.put(&2, &1))
      Enum.reduce(parents, visited, &collect_ancestors(&1, &2, opts))
    end
  end

  defp collect_descendants(person_id, visited, opts) do
    if MapSet.member?(visited, person_id) do
      visited
    else
      children =
        Ancestry.Relationships.get_children(person_id, opts)
        |> Enum.map(& &1.id)

      visited = Enum.reduce(children, visited, &MapSet.put(&2, &1))
      Enum.reduce(children, visited, &collect_descendants(&1, &2, opts))
    end
  end

  defp cleanup_family_files(family) do
    cover_dir = Path.join(["priv", "static", "uploads", "families", "#{family.id}"])
    File.rm_rf(cover_dir)

    photos_dir = Path.join(["priv", "static", "uploads", "photos", "#{family.id}"])
    File.rm_rf(photos_dir)
  end
end
