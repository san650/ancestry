defmodule Ancestry.Galleries.Gallery do
  use Ecto.Schema
  import Ecto.Changeset

  schema "galleries" do
    field :name, :string
    has_many :photos, Ancestry.Galleries.Photo, on_delete: :delete_all
    timestamps()
  end

  def changeset(gallery, attrs) do
    gallery
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
  end
end
