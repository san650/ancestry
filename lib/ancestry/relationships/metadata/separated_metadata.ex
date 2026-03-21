defmodule Ancestry.Relationships.Metadata.SeparatedMetadata do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :marriage_day, :integer
    field :marriage_month, :integer
    field :marriage_year, :integer
    field :marriage_location, :string
    field :separated_day, :integer
    field :separated_month, :integer
    field :separated_year, :integer
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [
      :marriage_day,
      :marriage_month,
      :marriage_year,
      :marriage_location,
      :separated_day,
      :separated_month,
      :separated_year
    ])
    |> validate_number(:marriage_month, greater_than_or_equal_to: 1, less_than_or_equal_to: 12)
    |> validate_number(:marriage_day, greater_than_or_equal_to: 1, less_than_or_equal_to: 31)
    |> validate_number(:marriage_year, greater_than_or_equal_to: 1, less_than_or_equal_to: 9999)
    |> validate_number(:separated_month, greater_than_or_equal_to: 1, less_than_or_equal_to: 12)
    |> validate_number(:separated_day, greater_than_or_equal_to: 1, less_than_or_equal_to: 31)
    |> validate_number(:separated_year, greater_than_or_equal_to: 1, less_than_or_equal_to: 9999)
  end
end
