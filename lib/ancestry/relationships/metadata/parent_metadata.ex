defmodule Ancestry.Relationships.Metadata.ParentMetadata do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
    field :role, :string
  end

  def changeset(struct, params) do
    struct
    |> cast(params, [:role])
    |> validate_required([:role])
    |> validate_inclusion(:role, ~w(father mother))
  end
end
