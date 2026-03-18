defmodule Ancestry.People.FamilyGraph.Node do
  @moduledoc """
  Represents a person node in the family graph with their generation number.
  """
  defstruct [:person, :generation]
end
