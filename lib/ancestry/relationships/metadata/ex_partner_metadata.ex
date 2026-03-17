defmodule Ancestry.Relationships.Metadata.ExPartnerMetadata do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :marriage_day, :integer
    field :marriage_month, :integer
    field :marriage_year, :integer
    field :marriage_location, :string
    field :divorce_day, :integer
    field :divorce_month, :integer
    field :divorce_year, :integer
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [
      :marriage_day,
      :marriage_month,
      :marriage_year,
      :marriage_location,
      :divorce_day,
      :divorce_month,
      :divorce_year
    ])
    |> validate_number(:marriage_month, greater_than_or_equal_to: 1, less_than_or_equal_to: 12)
    |> validate_number(:marriage_day, greater_than_or_equal_to: 1, less_than_or_equal_to: 31)
    |> validate_number(:marriage_year, greater_than_or_equal_to: 1, less_than_or_equal_to: 9999)
    |> validate_number(:divorce_month, greater_than_or_equal_to: 1, less_than_or_equal_to: 12)
    |> validate_number(:divorce_day, greater_than_or_equal_to: 1, less_than_or_equal_to: 31)
    |> validate_number(:divorce_year, greater_than_or_equal_to: 1, less_than_or_equal_to: 9999)
  end
end
