defmodule Ancestry.Families.Family do
  use Ecto.Schema
  import Ecto.Changeset

  schema "families" do
    field :name, :string
    field :cover, :string
    field :cover_status, :string
    has_many :galleries, Ancestry.Galleries.Gallery, on_delete: :delete_all
    timestamps()
  end

  def changeset(family, attrs) do
    family
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
  end
end
