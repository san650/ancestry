defmodule Ancestry.Families.Family do
  use Ecto.Schema
  use Waffle.Ecto.Schema
  import Ecto.Changeset

  schema "families" do
    field :name, :string
    field :cover, Ancestry.Uploaders.FamilyCover.Type
    field :cover_status, :string
    has_many :galleries, Ancestry.Galleries.Gallery, on_delete: :delete_all
    many_to_many :members, Ancestry.People.Person, join_through: "family_members"
    timestamps()
  end

  def changeset(family, attrs) do
    family
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
  end
end
