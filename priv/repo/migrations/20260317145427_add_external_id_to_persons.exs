defmodule Ancestry.Repo.Migrations.AddExternalIdToPersons do
  use Ecto.Migration

  def change do
    alter table(:persons) do
      add :external_id, :text
    end

    create unique_index(:persons, [:external_id])
  end
end
