defmodule Ancestry.Organizations.Organization do
  use Ecto.Schema
  import Ecto.Changeset

  schema "organizations" do
    field :name, :string

    has_many :families, Ancestry.Families.Family, on_delete: :delete_all
    has_many :people, Ancestry.People.Person, on_delete: :delete_all

    timestamps()
  end

  def changeset(organization, attrs) do
    organization
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
  end
end
