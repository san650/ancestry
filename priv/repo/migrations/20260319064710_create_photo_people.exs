defmodule Ancestry.Repo.Migrations.CreatePhotoPeople do
  use Ecto.Migration

  def change do
    create table(:photo_people) do
      add :photo_id, references(:photos, on_delete: :delete_all), null: false
      add :person_id, references(:persons, on_delete: :delete_all), null: false
      add :x, :float, null: false
      add :y, :float, null: false

      timestamps(updated_at: false)
    end

    create index(:photo_people, [:photo_id])
    create index(:photo_people, [:person_id])
    create unique_index(:photo_people, [:photo_id, :person_id])
  end
end
