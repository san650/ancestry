defmodule Ancestry.People.PersonTree do
  @moduledoc """
  Builds a person-centered family tree with N generations of ancestors
  above and N generations of descendants below a focus person.
  """

  alias Ancestry.People.Person
  alias Ancestry.Relationships

  @max_depth 3

  defstruct [:focus_person, :ancestors, :center, :descendants]

  @doc """
  Builds a person-centered tree from the given focus person.

  Returns a `%PersonTree{}` with:
  - `focus_person` — the Person struct
  - `ancestors` — list of generation rows from parents (index 0) to great-grandparents (index 2)
  - `center` — map with focus person, partner, ex-partners with children, partner children, solo children
  - `descendants` — list of generation rows from children (index 0) to great-grandchildren (index 2)
  """
  def build(%Person{} = focus_person) do
    center = build_center(focus_person)
    ancestors = build_ancestors([focus_person.id], 0)
    descendants = build_descendants(center, 0)

    %__MODULE__{
      focus_person: focus_person,
      ancestors: ancestors,
      center: center,
      descendants: descendants
    }
  end

  # --- Center Row ---

  defp build_center(focus_person) do
    partners = Relationships.get_partners(focus_person.id)
    ex_partners = Relationships.get_ex_partners(focus_person.id)

    # Take the first current partner for the center pair
    {partner, _partner_rel} =
      case partners do
        [{person, rel} | _] -> {person, rel}
        [] -> {nil, nil}
      end

    # Children with current partner
    partner_children =
      if partner do
        Relationships.get_children_of_pair(focus_person.id, partner.id)
      else
        []
      end

    # Children with each ex-partner
    ex_partner_groups =
      Enum.map(ex_partners, fn {ex, _rel} ->
        children = Relationships.get_children_of_pair(focus_person.id, ex.id)
        %{person: ex, children: children}
      end)

    # Solo children (no co-parent)
    solo_children = Relationships.get_solo_children(focus_person.id)

    %{
      focus: focus_person,
      partner: partner,
      ex_partners: ex_partner_groups,
      partner_children: partner_children,
      solo_children: solo_children
    }
  end

  # --- Ancestors ---

  @doc false
  def build_ancestors(_person_ids, depth) when depth >= @max_depth, do: []

  def build_ancestors([], _depth), do: []

  def build_ancestors(person_ids, depth) do
    # For each person, get their parents as a couple
    couples =
      Enum.map(person_ids, fn person_id ->
        parents = Relationships.get_parents(person_id)

        case parents do
          [] ->
            %{person_a: nil, person_b: nil}

          [{parent, _rel}] ->
            %{person_a: parent, person_b: nil}

          [{p1, _r1}, {p2, _r2} | _] ->
            %{person_a: p1, person_b: p2}
        end
      end)

    # If all couples are empty (no parents found), stop
    if Enum.all?(couples, fn c -> is_nil(c.person_a) and is_nil(c.person_b) end) do
      []
    else
      # Collect parent IDs for the next generation up
      next_person_ids =
        Enum.flat_map(couples, fn couple ->
          [couple.person_a, couple.person_b]
          |> Enum.reject(&is_nil/1)
          |> Enum.map(& &1.id)
        end)

      [couples | build_ancestors(next_person_ids, depth + 1)]
    end
  end

  # --- Descendants ---

  defp build_descendants(_center, depth) when depth >= @max_depth, do: []

  defp build_descendants(center, 0) do
    # First generation: children from the center row
    family_units = build_family_units_from_center(center)

    if Enum.empty?(family_units) do
      []
    else
      [family_units | build_descendant_generations(family_units, 1)]
    end
  end

  defp build_family_units_from_center(center) do
    units = []

    # Partner children
    units =
      if center.partner_children != [] do
        children_units =
          Enum.map(center.partner_children, fn child ->
            build_child_unit(child)
          end)

        units ++ children_units
      else
        units
      end

    # Ex-partner children
    units =
      Enum.reduce(center.ex_partners, units, fn ex_group, acc ->
        children_units =
          Enum.map(ex_group.children, fn child ->
            build_child_unit(child)
          end)

        acc ++ children_units
      end)

    # Solo children
    units =
      if center.solo_children != [] do
        children_units =
          Enum.map(center.solo_children, fn child ->
            build_child_unit(child)
          end)

        units ++ children_units
      else
        units
      end

    units
  end

  defp build_descendant_generations(_family_units, depth) when depth >= @max_depth, do: []

  defp build_descendant_generations(family_units, depth) do
    at_last_level = depth + 1 >= @max_depth

    # For each family unit in the current generation, get their children
    next_units =
      Enum.flat_map(family_units, fn unit ->
        get_children_for_unit(unit, check_more: at_last_level)
      end)

    if Enum.empty?(next_units) do
      []
    else
      [next_units | build_descendant_generations(next_units, depth + 1)]
    end
  end

  defp build_child_unit(child, opts \\ []) do
    check_more = Keyword.get(opts, :check_more, false)
    partners = Relationships.get_partners(child.id)

    partner =
      case partners do
        [{person, _rel} | _] -> person
        [] -> nil
      end

    has_more =
      if check_more do
        Relationships.get_children(child.id) != []
      else
        false
      end

    %{person: child, partner: partner, has_more: has_more}
  end

  defp get_children_for_unit(%{person: person, partner: partner}, opts) do
    children =
      if partner do
        paired = Relationships.get_children_of_pair(person.id, partner.id)
        solo = Relationships.get_solo_children(person.id)
        paired ++ solo
      else
        Relationships.get_children(person.id)
      end

    Enum.map(children, fn child ->
      build_child_unit(child, opts)
    end)
  end
end
