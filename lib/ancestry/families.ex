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

    bfs_traverse(
      MapSet.new(),
      [{person_id, :direct}],
      source_family_id,
      include_partner_ancestors
    )
  end

  defp bfs_traverse(visited, [], _family_id, _include_partner_ancestors), do: visited

  defp bfs_traverse(visited, queue, family_id, include_partner_ancestors) do
    opts = [family_id: family_id]

    {new_visited, new_queue} =
      Enum.reduce(queue, {visited, []}, fn {person_id, traversal_type}, {vis, q} ->
        if MapSet.member?(vis, person_id) do
          {vis, q}
        else
          vis = MapSet.put(vis, person_id)

          parent_ids =
            if traversal_type == :via_partner and not include_partner_ancestors do
              []
            else
              Ancestry.Relationships.get_parents(person_id, opts)
              |> Enum.map(fn {person, _rel} -> {person.id, :direct} end)
            end

          child_ids =
            Ancestry.Relationships.get_children(person_id, opts)
            |> Enum.map(fn child -> {child.id, :direct} end)

          active_partner_ids =
            Ancestry.Relationships.get_active_partners(person_id, opts)
            |> Enum.map(fn {person, _rel} -> {person.id, :via_partner} end)

          former_partner_ids =
            Ancestry.Relationships.get_former_partners(person_id, opts)
            |> Enum.map(fn {person, _rel} -> {person.id, :via_partner} end)

          neighbors = parent_ids ++ child_ids ++ active_partner_ids ++ former_partner_ids
          unvisited = Enum.reject(neighbors, fn {id, _type} -> MapSet.member?(vis, id) end)

          {vis, q ++ unvisited}
        end
      end)

    bfs_traverse(new_visited, new_queue, family_id, include_partner_ancestors)
  end

  defp cleanup_family_files(family) do
    cover_dir = Path.join(["priv", "static", "uploads", "families", "#{family.id}"])
    File.rm_rf(cover_dir)

    photos_dir = Path.join(["priv", "static", "uploads", "photos", "#{family.id}"])
    File.rm_rf(photos_dir)
  end
end
