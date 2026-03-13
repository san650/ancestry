defmodule Ancestry.Repo.Migrations.CreateFamilyMembers do
  use Ecto.Migration

  def change do
    create table(:family_members) do
      add :family_id, references(:families, on_delete: :delete_all), null: false
      add :person_id, references(:persons, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:family_members, [:family_id])
    create index(:family_members, [:person_id])
    create unique_index(:family_members, [:family_id, :person_id])
  end
end
