defmodule Ancestry.Repo.Migrations.AddFileHashToPhotos do
  use Ecto.Migration

  def change do
    alter table(:photos) do
      add :file_hash, :string
    end

    create unique_index(:photos, [:gallery_id, :file_hash],
             where: "file_hash IS NOT NULL",
             name: :photos_gallery_id_file_hash_index
           )
  end
end
