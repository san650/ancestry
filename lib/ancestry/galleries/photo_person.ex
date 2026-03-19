defmodule Ancestry.Galleries.PhotoPerson do
  use Ecto.Schema
  import Ecto.Changeset

  schema "photo_people" do
    belongs_to :photo, Ancestry.Galleries.Photo
    belongs_to :person, Ancestry.People.Person

    field :x, :float
    field :y, :float

    timestamps(updated_at: false)
  end

  def changeset(photo_person, attrs) do
    photo_person
    |> cast(attrs, [:x, :y])
    |> validate_required([:x, :y])
    |> validate_number(:x, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:y, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> foreign_key_constraint(:photo_id)
    |> foreign_key_constraint(:person_id)
    |> unique_constraint([:photo_id, :person_id])
  end
end
