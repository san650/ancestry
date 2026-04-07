defmodule Ancestry.Repo.Migrations.ScopePersonExternalIdToOrganization do
  use Ecto.Migration

  def change do
    drop unique_index(:persons, [:external_id])
    create unique_index(:persons, [:organization_id, :external_id])
  end
end
