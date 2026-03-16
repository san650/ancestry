defmodule Ancestry.Repo.Migrations.CreatePhotoComments do
  use Ecto.Migration

  def change do
    create table(:photo_comments) do
      add :text, :text, null: false
      add :photo_id, references(:photos, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:photo_comments, [:photo_id])
  end
end
