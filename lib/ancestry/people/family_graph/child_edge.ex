defmodule Ancestry.People.FamilyGraph.ChildEdge do
  @moduledoc """
  Represents a parent-to-child edge.

  `:from` is `{:union, id}` when both parents have a union, or `{:person, id}`
  when a single parent is known (or parents have no union between them).
  `:to` is the child's person_id.
  """
  defstruct [:from, :to]
end
