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
    family = Repo.preload(family, galleries: :photos)
    files_to_clean = collect_files_for(family)

    case Repo.delete(family, stale_error_field: :id) do
      {:ok, deleted} ->
        cleanup_files_after_delete(files_to_clean)
        {:ok, deleted}

      {:error, _changeset} = err ->
        err
    end
  end

  @doc false
  # Public so the Organizations context can reuse the same cleanup pipeline.
  def collect_files_for(%Family{} = family) do
    photos =
      for gallery <- family.galleries,
          photo <- gallery.photos do
        # Attach the gallery in memory so the Waffle uploader's storage_dir/2,
        # which reads photo.gallery.family_id, doesn't fault on NotLoaded.
        {:photo, %{photo | gallery: gallery}}
      end

    local_dirs = [
      Path.join(["priv", "static", "uploads", "families", "#{family.id}"]),
      Path.join(["priv", "static", "uploads", "photos", "#{family.id}"])
    ]

    %{photos: photos, local_dirs: local_dirs}
  end

  @doc false
  # Public so the Organizations context can reuse the same cleanup pipeline.
  def cleanup_files_after_delete(%{photos: photos, local_dirs: dirs}) do
    require Logger

    Enum.each(photos, fn {:photo, photo} ->
      if photo.image do
        try do
          Ancestry.Uploaders.Photo.delete({photo.image, photo})
        rescue
          e -> Logger.warning("Photo cleanup failed: #{inspect(e)}")
        end
      end
    end)

    Enum.each(dirs, fn dir ->
      try do
        File.rm_rf(dir)
      rescue
        e -> Logger.warning("Local dir cleanup failed: #{inspect(e)}")
      end
    end)

    :ok
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

    * `:include_ancestors` - when `true`, includes the person's ascendants.
      Defaults to `true`.
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
    include_ancestors = Keyword.get(opts, :include_ancestors, true)
    include_partner_ancestors = Keyword.get(opts, :include_partner_ancestors, false)
    family_opts = [family_id: source_family_id]

    ancestors =
      if include_ancestors do
        collect_ancestors(person_id, MapSet.new(), family_opts)
      else
        MapSet.new()
      end

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
    parents =
      Ancestry.Relationships.get_parents(person_id, opts)
      |> Enum.map(fn {person, _rel} -> person.id end)
      |> Enum.reject(&MapSet.member?(visited, &1))

    visited = Enum.reduce(parents, visited, &MapSet.put(&2, &1))
    Enum.reduce(parents, visited, &collect_ancestors(&1, &2, opts))
  end

  defp collect_descendants(person_id, visited, opts) do
    # Include this person's partners (but don't recurse into their descendants)
    partner_ids =
      (Ancestry.Relationships.get_active_partners(person_id, opts) ++
         Ancestry.Relationships.get_former_partners(person_id, opts))
      |> Enum.map(fn {person, _rel} -> person.id end)
      |> Enum.reject(&MapSet.member?(visited, &1))

    visited = Enum.reduce(partner_ids, visited, &MapSet.put(&2, &1))

    # Walk down through children only (not partner's children)
    children =
      Ancestry.Relationships.get_children(person_id, opts)
      |> Enum.map(& &1.id)
      |> Enum.reject(&MapSet.member?(visited, &1))

    visited = Enum.reduce(children, visited, &MapSet.put(&2, &1))
    Enum.reduce(children, visited, &collect_descendants(&1, &2, opts))
  end
end
