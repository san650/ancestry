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
  - `descendants` — list of family units (recursive tree structure, not flat rows)
  """
  def build(%Person{} = focus_person) do
    center = build_center(focus_person)
    ancestors = build_ancestors([focus_person.id], 0)

    %__MODULE__{
      focus_person: focus_person,
      ancestors: ancestors,
      center: center
    }
  end

  # --- Center Row ---

  defp build_center(focus_person) do
    build_family_unit_full(focus_person, 0)
  end

  @doc """
  Builds a full family unit for a person, including partner, ex-partners,
  and children grouped by couple. Recurses for descendant generations.
  """
  def build_family_unit_full(person, depth) do
    partners = Relationships.get_partners(person.id)
    ex_partners = Relationships.get_ex_partners(person.id)

    # Take the first current partner for the center pair
    {partner, _partner_rel} =
      case partners do
        [{p, rel} | _] -> {p, rel}
        [] -> {nil, nil}
      end

    at_limit = depth + 1 >= @max_depth

    # Children with current partner
    partner_children =
      if partner do
        Relationships.get_children_of_pair(person.id, partner.id)
        |> build_child_units(depth, at_limit)
      else
        []
      end

    # Children with each ex-partner
    ex_partner_groups =
      Enum.map(ex_partners, fn {ex, _rel} ->
        children =
          Relationships.get_children_of_pair(person.id, ex.id)
          |> build_child_units(depth, at_limit)

        %{person: ex, children: children}
      end)

    # Solo children (no co-parent)
    solo_children =
      Relationships.get_solo_children(person.id)
      |> build_child_units(depth, at_limit)

    %{
      focus: person,
      partner: partner,
      ex_partners: ex_partner_groups,
      partner_children: partner_children,
      solo_children: solo_children
    }
  end

  defp build_child_units(_children, depth, _at_limit) when depth >= @max_depth, do: []

  defp build_child_units(children, depth, at_limit) do
    Enum.map(children, fn child ->
      if at_limit do
        # At the limit — just check if they have more, don't recurse
        has_more = Relationships.get_children(child.id) != []
        partners = Relationships.get_partners(child.id)

        partner =
          case partners do
            [{p, _} | _] -> p
            [] -> nil
          end

        %{person: child, partner: partner, has_more: has_more, children: nil}
      else
        # Recurse to build the full subtree
        unit = build_family_unit_full(child, depth + 1)

        has_children =
          unit.partner_children != [] or unit.solo_children != [] or unit.ex_partners != []

        Map.put(unit, :has_more, false) |> Map.put(:has_children, has_children)
      end
    end)
  end

  # --- Ancestors ---

  @doc false
  def build_ancestors(_person_ids, depth) when depth >= @max_depth, do: []

  def build_ancestors([], _depth), do: []

  def build_ancestors(person_ids, depth) do
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

    if Enum.all?(couples, fn c -> is_nil(c.person_a) and is_nil(c.person_b) end) do
      []
    else
      next_person_ids =
        Enum.flat_map(couples, fn couple ->
          [couple.person_a, couple.person_b]
          |> Enum.reject(&is_nil/1)
          |> Enum.map(& &1.id)
        end)

      [couples | build_ancestors(next_person_ids, depth + 1)]
    end
  end
end
