defmodule Ancestry.Repo.Migrations.CreateMemoryMentions do
  use Ecto.Migration

  def change do
    create table(:memory_mentions) do
      add :memory_id, references(:memories, on_delete: :delete_all), null: false
      add :person_id, references(:persons, on_delete: :delete_all), null: false
    end

    create unique_index(:memory_mentions, [:memory_id, :person_id])
    create index(:memory_mentions, [:person_id])
  end
end
