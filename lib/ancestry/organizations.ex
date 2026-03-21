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
    Repo.delete(org)
  end

  def change_organization(%Organization{} = org, attrs \\ %{}) do
    Organization.changeset(org, attrs)
  end
end
