defmodule Ancestry.People.GraphNode do
  @moduledoc """
  A cell in the DAG grid — either a person or a separator.

  Person nodes carry the person struct and metadata (focus, duplicated, has_more).
  Separator nodes are empty cells for centering, group boundaries, or width equalization.
  """

  defstruct [
    :id,
    :type,
    :col,
    :row,
    :person,
    focus: false,
    duplicated: false,
    has_more_up: false,
    has_more_down: false
  ]
end
