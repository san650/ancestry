defmodule Ancestry.People.FamilyGraph.Grid do
  @moduledoc """
  A 2D grid of cells representing a family graph layout.

  `rows` and `cols` give the grid dimensions.
  `cells` is a map of `{row, col} => %Cell{}` entries.
  """
  alias Ancestry.People.FamilyGraph.Cell

  defstruct rows: 0, cols: 0, cells: %{}

  @type t :: %__MODULE__{
          rows: non_neg_integer(),
          cols: non_neg_integer(),
          cells: %{{non_neg_integer(), non_neg_integer()} => Cell.t()}
        }
end
