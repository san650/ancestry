defmodule Ancestry.People.PersonGraph.LayoutTest do
  use ExUnit.Case, async: true

  alias Ancestry.People.PersonGraph.Layout

  describe "compute/2" do
    test "returns an empty triple for an empty state" do
      state = %{entries: %{}, edges: [], visited: %{}, graph: nil, focus_id: nil}
      assert {[], 0, 0} = Layout.compute(state, nil)
    end
  end
end
