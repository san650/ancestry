defmodule Ancestry.People.FamilyMember do
  use Ecto.Schema
  import Ecto.Changeset

  schema "family_members" do
    belongs_to :family, Ancestry.Families.Family
    belongs_to :person, Ancestry.People.Person

    field :is_default, :boolean, default: false

    timestamps()
  end

  def changeset(family_member, attrs) do
    family_member
    |> cast(attrs, [])
    |> foreign_key_constraint(:family_id)
    |> foreign_key_constraint(:person_id)
    |> unique_constraint([:family_id, :person_id])
  end
end
