defmodule Ancestry.Repo.Migrations.CreateOrganizations do
  use Ecto.Migration

  def change do
    create table(:organizations) do
      add :name, :text, null: false
      timestamps()
    end
  end
end
