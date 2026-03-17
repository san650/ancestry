defmodule Ancestry.Relationships.Metadata.PartnerMetadata do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :marriage_day, :integer
    field :marriage_month, :integer
    field :marriage_year, :integer
    field :marriage_location, :string
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [:marriage_day, :marriage_month, :marriage_year, :marriage_location])
    |> validate_number(:marriage_month, greater_than_or_equal_to: 1, less_than_or_equal_to: 12)
    |> validate_number(:marriage_day, greater_than_or_equal_to: 1, less_than_or_equal_to: 31)
    |> validate_number(:marriage_year, greater_than_or_equal_to: 1, less_than_or_equal_to: 9999)
  end
end
