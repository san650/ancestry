defmodule Family.Repo.Migrations.CreateGalleries do
  use Ecto.Migration

  def change do
    create table(:galleries) do
      add :name, :text, null: false
      timestamps()
    end
  end
end
