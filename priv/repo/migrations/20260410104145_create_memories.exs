defmodule Ancestry.Repo.Migrations.CreateMemories do
  use Ecto.Migration

  def change do
    create table(:memories) do
      add :name, :string, null: false
      add :content, :text
      add :description, :string
      add :cover_photo_id, references(:photos, on_delete: :nilify_all)
      add :memory_vault_id, references(:memory_vaults, on_delete: :delete_all), null: false
      add :inserted_by, references(:accounts, on_delete: :nilify_all)
      timestamps()
    end

    create index(:memories, [:memory_vault_id])
    create index(:memories, [:cover_photo_id])
    create index(:memories, [:inserted_by])
  end
end
