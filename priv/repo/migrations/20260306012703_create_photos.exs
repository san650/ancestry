defmodule Family.Repo.Migrations.CreatePhotos do
  use Ecto.Migration

  def change do
    create table(:photos) do
      add :gallery_id, references(:galleries, on_delete: :delete_all), null: false
      add :image, :text
      add :original_path, :text
      add :original_filename, :text
      add :content_type, :text
      add :status, :text, null: false, default: "pending"
      timestamps(updated_at: false)
    end

    create index(:photos, [:gallery_id])
  end
end
