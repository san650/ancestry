defmodule Ancestry.People.Person do
  use Ecto.Schema
  use Waffle.Ecto.Schema
  import Ecto.Changeset

  schema "persons" do
    field :given_name, :string
    field :surname, :string
    field :given_name_at_birth, :string
    field :surname_at_birth, :string
    field :nickname, :string
    field :title, :string
    field :suffix, :string
    field :alternate_names, {:array, :string}, default: []
    field :birth_day, :integer
    field :birth_month, :integer
    field :birth_year, :integer
    field :death_day, :integer
    field :death_month, :integer
    field :death_year, :integer
    field :deceased, :boolean, default: false
    field :gender, :string
    field :external_id, :string
    field :photo, Ancestry.Uploaders.PersonPhoto.Type
    field :photo_status, :string
    field :kind, :string, default: "family_member"
    field :name_search, :string

    belongs_to :organization, Ancestry.Organizations.Organization
    many_to_many :families, Ancestry.Families.Family, join_through: "family_members"

    has_many :photo_people, Ancestry.Galleries.PhotoPerson
    has_many :photos, through: [:photo_people, :photo]

    timestamps()
  end

  @cast_fields [
    :given_name,
    :surname,
    :given_name_at_birth,
    :surname_at_birth,
    :nickname,
    :title,
    :suffix,
    :alternate_names,
    :birth_day,
    :birth_month,
    :birth_year,
    :death_day,
    :death_month,
    :death_year,
    :deceased,
    :gender,
    :external_id,
    :kind
  ]

  def changeset(person, attrs) do
    person
    |> cast(attrs, @cast_fields)
    |> default_birth_names()
    |> compute_name_search()
    |> validate_inclusion(:gender, ~w(female male other))
    |> validate_inclusion(:kind, ~w(family_member acquaintance))
    |> validate_number(:birth_month, greater_than_or_equal_to: 1, less_than_or_equal_to: 12)
    |> validate_number(:birth_day, greater_than_or_equal_to: 1, less_than_or_equal_to: 31)
    |> validate_number(:birth_year, greater_than_or_equal_to: 1, less_than_or_equal_to: 9999)
    |> validate_number(:death_month, greater_than_or_equal_to: 1, less_than_or_equal_to: 12)
    |> validate_number(:death_day, greater_than_or_equal_to: 1, less_than_or_equal_to: 31)
    |> validate_number(:death_year, greater_than_or_equal_to: 1, less_than_or_equal_to: 9999)
    |> unique_constraint(:external_id, name: :persons_organization_id_external_id_index)
  end

  defp compute_name_search(changeset) do
    fields = [
      get_field(changeset, :given_name),
      get_field(changeset, :surname),
      get_field(changeset, :given_name_at_birth),
      get_field(changeset, :surname_at_birth),
      get_field(changeset, :nickname)
    ]

    alt_names = get_field(changeset, :alternate_names) || []

    name_search =
      (fields ++ alt_names)
      |> Enum.reject(&(is_nil(&1) or &1 == ""))
      |> Enum.join(" ")
      |> Ancestry.StringUtils.normalize()

    put_change(changeset, :name_search, name_search)
  end

  defp default_birth_names(changeset) do
    changeset
    |> maybe_default(:given_name_at_birth, :given_name)
    |> maybe_default(:surname_at_birth, :surname)
  end

  defp maybe_default(changeset, birth_field, source_field) do
    if get_field(changeset, birth_field) do
      changeset
    else
      put_change(changeset, birth_field, get_field(changeset, source_field))
    end
  end

  def photo_changeset(person, attrs) do
    person
    |> cast_attachments(attrs, [:photo])
    |> cast(attrs, [:photo_status])
  end

  def display_name(%__MODULE__{given_name: given, surname: sur}) do
    [given, sur]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  def acquaintance?(%__MODULE__{kind: "acquaintance"}), do: true
  def acquaintance?(%__MODULE__{}), do: false
end
