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
    |> maybe_validate_coordinate_range(:x)
    |> maybe_validate_coordinate_range(:y)
    |> foreign_key_constraint(:photo_id)
    |> foreign_key_constraint(:person_id)
    |> unique_constraint([:photo_id, :person_id])
  end

  defp maybe_validate_coordinate_range(changeset, field) do
    case get_field(changeset, field) do
      nil ->
        changeset

      _ ->
        validate_number(changeset, field,
          greater_than_or_equal_to: 0.0,
          less_than_or_equal_to: 1.0
        )
    end
  end
end
