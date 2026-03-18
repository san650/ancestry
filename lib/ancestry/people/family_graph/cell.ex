defmodule Ancestry.People.FamilyGraph.Cell do
  @moduledoc """
  A single cell in the family graph grid.

  ## Types

  - `:person` — a person node; `data` has `:person_id`
  - `:union` — a union node; `data` has `:union_id`
  - `:vertical` — vertical connector line
  - `:horizontal` — horizontal connector line
  - `:t_down` — T-junction pointing downward (source of child lines)
  - `:top_left` — corner turning from right to down
  - `:top_right` — corner turning from left to down
  - `:bottom_left` — corner turning from right to up
  - `:bottom_right` — corner turning from left to up
  """

  defstruct [:type, :data]

  @type cell_type ::
          :person
          | :union
          | :vertical
          | :horizontal
          | :t_down
          | :top_left
          | :top_right
          | :bottom_left
          | :bottom_right

  @type t :: %__MODULE__{
          type: cell_type(),
          data: map() | nil
        }
end
