defmodule Ancestry.People.PersonGraph.Layout do
  @moduledoc """
  Bottom-up subtree-width allocation layout for `PersonGraph`.

  Consumes Phase-1 traversal output (entries grouped by generation + edges +
  focus_id) and produces a flat `(nodes, grid_cols, grid_rows)` triple ready
  to be returned from `PersonGraph.build/3`.

  See `docs/plans/2026-04-28-graph-clustering-design.md` for the algorithm.
  """

  defmodule Couple do
    @moduledoc false
    defstruct [:anchor_a, :anchor_b, children: []]
  end

  defmodule Single do
    @moduledoc false
    defstruct [:anchor, children: []]
  end

  defmodule LooseLane do
    @moduledoc false
    defstruct units: []
  end

  @doc """
  Computes the layout for the given Phase-1 state.

  Returns `{nodes, grid_cols, grid_rows}` where `nodes` is a flat list of
  `%GraphNode{}` cells (persons + separators), `grid_cols` is the maximum
  column count, and `grid_rows` is `max_gen - min_gen + 1`.
  """
  def compute(%{entries: entries} = _state, _focus_id) when map_size(entries) == 0 do
    {[], 0, 0}
  end

  def compute(_state, _focus_id) do
    # Real implementation arrives in Tasks 2-7.
    {[], 0, 0}
  end
end
