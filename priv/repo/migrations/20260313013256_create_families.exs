defmodule Ancestry.Repo.Migrations.CreateFamilies do
  use Ecto.Migration

  def change do
    create table(:families) do
      add :name, :text, null: false
      add :cover, :text
      add :cover_status, :text
      timestamps()
    end
  end
end
