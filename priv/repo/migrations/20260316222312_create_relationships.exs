defmodule Ancestry.Repo.Migrations.CreateRelationships do
  use Ecto.Migration

  def change do
    create table(:relationships) do
      add :person_a_id, references(:persons, on_delete: :delete_all), null: false
      add :person_b_id, references(:persons, on_delete: :delete_all), null: false
      add :type, :string, null: false
      add :metadata, :map, default: %{}

      timestamps()
    end

    create unique_index(:relationships, [:person_a_id, :person_b_id, :type])
    create index(:relationships, [:person_b_id])
  end
end
