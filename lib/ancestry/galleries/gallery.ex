defmodule Ancestry.Galleries.Gallery do
  use Ecto.Schema
  import Ecto.Changeset

  schema "galleries" do
    field :name, :string
    belongs_to :family, Ancestry.Families.Family
    has_many :photos, Ancestry.Galleries.Photo, on_delete: :delete_all
    timestamps()
  end

  def changeset(gallery, attrs) do
    gallery
    |> cast(attrs, [:name, :family_id])
    |> validate_required([:name, :family_id])
    |> validate_length(:name, min: 1, max: 255)
    |> foreign_key_constraint(:family_id)
  end
end
