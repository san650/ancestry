defmodule Ancestry.Relationships.Metadata.RelationshipMetadata do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false

  embedded_schema do
  end

  def changeset(struct, params) do
    cast(struct, params, [])
  end
end
