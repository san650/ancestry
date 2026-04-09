defmodule Ancestry.Organizations do
  import Ecto.Query
  alias Ancestry.Repo
  alias Ancestry.Organizations.Organization

  def list_organizations do
    Repo.all(from o in Organization, order_by: [asc: o.name])
  end

  def get_organization!(id), do: Repo.get!(Organization, id)

  def create_organization(attrs \\ %{}) do
    %Organization{}
    |> Organization.changeset(attrs)
    |> Repo.insert()
  end

  def update_organization(%Organization{} = org, attrs) do
    org
    |> Organization.changeset(attrs)
    |> Repo.update()
  end

  def delete_organization(%Organization{} = org) do
    # Preload everything we need for file cleanup BEFORE the delete so the
    # struct carries the gallery, photo, cover, and person_photo references
    # we need to reach Waffle's `delete/1`. After `Repo.delete/1` the rows
    # are gone from the DB, but our in-memory manifest still knows what
    # to clean up on disk (or S3 in production).
    org = Repo.preload(org, [:people, families: [galleries: :photos]])
    files_to_clean = collect_org_files(org)

    case Repo.delete(org, stale_error_field: :id) do
      {:ok, deleted} ->
        Ancestry.Families.cleanup_files_after_delete(files_to_clean)
        {:ok, deleted}

      {:error, _changeset} = err ->
        err
    end
  end

  defp collect_org_files(%Organization{} = org) do
    # Use Enum.flat_map to avoid the previous O(n^2) list concatenation —
    # with N families and M photos each, `acc.photos ++ family_files.photos`
    # rebuilt the growing accumulator on every iteration.
    family_manifests = Enum.map(org.families, &Ancestry.Families.collect_files_for/1)

    family_files = Enum.flat_map(family_manifests, & &1.files)
    family_local_dirs = Enum.flat_map(family_manifests, & &1.local_dirs)

    # Persons are cascaded by the org schema's `has_many :people,
    # on_delete: :delete_all`, so org delete is the ONLY path that needs
    # to clean up PersonPhoto uploads. delete_family/1 must NOT clean
    # these — persons survive family deletion via the family_members
    # join table.
    person_files =
      org.people
      |> Enum.filter(& &1.photo)
      |> Enum.map(&{:person_photo, &1})

    %{
      files: family_files ++ person_files,
      local_dirs: family_local_dirs
    }
  end

  def change_organization(%Organization{} = org, attrs \\ %{}) do
    Organization.changeset(org, attrs)
  end
end
