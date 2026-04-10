defmodule Ancestry.Repo.Migrations.CreateMemoryVaults do
  use Ecto.Migration

  def change do
    create table(:memory_vaults) do
      add :name, :string, null: false
      add :family_id, references(:families, on_delete: :delete_all), null: false
      timestamps()
    end

    create index(:memory_vaults, [:family_id])
  end
end
