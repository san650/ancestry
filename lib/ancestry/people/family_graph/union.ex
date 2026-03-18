defmodule Ancestry.People.FamilyGraph.Union do
  @moduledoc """
  Represents a partnership (partner or ex_partner) between two people.
  """
  defstruct [:person_a_id, :person_b_id, :type, :id]
end
