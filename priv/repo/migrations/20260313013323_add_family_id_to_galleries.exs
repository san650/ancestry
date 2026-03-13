defmodule Ancestry.Repo.Migrations.AddFamilyIdToGalleries do
  use Ecto.Migration

  def change do
    alter table(:galleries) do
      add :family_id, references(:families, on_delete: :delete_all), null: false
    end

    create index(:galleries, [:family_id])
  end
end
