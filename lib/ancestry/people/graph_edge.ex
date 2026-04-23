defmodule Ancestry.People.GraphEdge do
  @moduledoc """
  A connection between two GraphNodes in the DAG.

  `type` is structural (determines connector routing):
  - `:parent_child` — vertical routing between rows
  - `:current_partner` — horizontal routing, after the person
  - `:previous_partner` — horizontal routing, before the person

  `relationship_kind` is visual (determines CSS styling):
  maps to `Ancestry.Relationships.Relationship` type field.
  """

  @derive Jason.Encoder

  defstruct [
    :type,
    :relationship_kind,
    :from_id,
    :to_id
  ]
end
