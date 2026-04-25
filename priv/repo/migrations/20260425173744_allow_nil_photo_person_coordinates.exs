defmodule Ancestry.Repo.Migrations.AllowNilPhotoPersonCoordinates do
  use Ecto.Migration

  def change do
    alter table(:photo_people) do
      modify :x, :float, null: true, from: {:float, null: false}
      modify :y, :float, null: true, from: {:float, null: false}
    end
  end
end
