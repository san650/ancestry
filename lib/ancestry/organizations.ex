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
    org = Repo.preload(org, families: [galleries: :photos])
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
    org.families
    |> Enum.reduce(%{photos: [], local_dirs: []}, fn family, acc ->
      family_files = Ancestry.Families.collect_files_for(family)

      %{
        photos: acc.photos ++ family_files.photos,
        local_dirs: acc.local_dirs ++ family_files.local_dirs
      }
    end)
  end

  def change_organization(%Organization{} = org, attrs \\ %{}) do
    Organization.changeset(org, attrs)
  end
end
