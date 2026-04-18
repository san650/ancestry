defmodule Ancestry.People.PersonTree do
  @moduledoc """
  Builds a person-centered family tree with N generations of ancestors
  above and N generations of descendants below a focus person.
  """

  alias Ancestry.People.FamilyGraph
  alias Ancestry.People.Person

  @max_depth 3

  defstruct [:focus_person, :ancestors, :center, :descendants, :family_id]

  @doc """
  Builds a person-centered tree. Accepts a family_id (builds graph internally)
  or a pre-built %FamilyGraph{} (zero queries).
  """
  def build(%Person{} = focus_person, family_id) when is_integer(family_id) do
    build(focus_person, FamilyGraph.for_family(family_id))
  end

  def build(%Person{} = focus_person, %FamilyGraph{} = graph) do
    center = build_family_unit_full(focus_person, 0, graph)
    ancestor_tree = build_ancestor_tree(focus_person.id, 0, graph)

    %__MODULE__{
      focus_person: focus_person,
      ancestors: ancestor_tree,
      center: center,
      family_id: graph.family_id
    }
  end

  # --- Center Row ---

  defp build_family_unit_full(person, depth, %FamilyGraph{} = graph) do
    partners = FamilyGraph.active_partners(graph, person.id)
    ex_partners = FamilyGraph.former_partners(graph, person.id)

    # Sort partners: latest marriage year first, then highest person id as tiebreaker
    sorted_partners =
      Enum.sort_by(
        partners,
        fn {p, rel} ->
          year = if rel.metadata, do: Map.get(rel.metadata, :marriage_year), else: nil
          {year || 0, p.id}
        end,
        :desc
      )

    # Latest partner is the main couple partner; rest are previous partners
    {partner, previous} =
      case sorted_partners do
        [{p, _rel} | rest] -> {p, rest}
        [] -> {nil, []}
      end

    at_limit = depth + 1 >= @max_depth

    # Children with current partner
    partner_children =
      if partner do
        FamilyGraph.children_of_pair(graph, person.id, partner.id)
        |> build_child_units(depth, at_limit, graph)
      else
        []
      end

    # Children with each previous (non-ex) partner
    previous_partner_groups =
      Enum.map(previous, fn {prev, _rel} ->
        children =
          FamilyGraph.children_of_pair(graph, person.id, prev.id)
          |> build_child_units(depth, at_limit, graph)

        %{person: prev, children: children}
      end)

    # Children with each ex-partner
    ex_partner_groups =
      Enum.map(ex_partners, fn {ex, _rel} ->
        children =
          FamilyGraph.children_of_pair(graph, person.id, ex.id)
          |> build_child_units(depth, at_limit, graph)

        %{person: ex, children: children}
      end)

    # Solo children (no co-parent)
    solo_children =
      FamilyGraph.solo_children(graph, person.id)
      |> build_child_units(depth, at_limit, graph)

    %{
      focus: person,
      partner: partner,
      previous_partners: previous_partner_groups,
      ex_partners: ex_partner_groups,
      partner_children: partner_children,
      solo_children: solo_children
    }
  end

  defp build_child_units(_children, depth, _at_limit, _graph) when depth >= @max_depth, do: []

  defp build_child_units(children, depth, at_limit, graph) do
    Enum.map(children, fn child ->
      if at_limit do
        # At the limit — just check if they have more, don't recurse
        has_more = FamilyGraph.has_children?(graph, child.id)
        partners = FamilyGraph.active_partners(graph, child.id)

        partner =
          case partners do
            [{p, _} | _] -> p
            [] -> nil
          end

        %{person: child, partner: partner, has_more: has_more, children: nil}
      else
        # Recurse to build the full subtree
        unit = build_family_unit_full(child, depth + 1, graph)

        has_children =
          unit.partner_children != [] or unit.solo_children != [] or unit.ex_partners != []

        Map.put(unit, :has_more, false) |> Map.put(:has_children, has_children)
      end
    end)
  end

  # --- Ancestors (recursive tree) ---

  defp build_ancestor_tree(_person_id, depth, _graph) when depth >= @max_depth, do: nil

  defp build_ancestor_tree(person_id, depth, graph) do
    parents = FamilyGraph.parents(graph, person_id)

    {person_a, person_b} =
      case parents do
        [] -> {nil, nil}
        [{p, _}] -> {p, nil}
        [{p1, _}, {p2, _} | _] -> {p1, p2}
      end

    if is_nil(person_a) and is_nil(person_b) do
      nil
    else
      parent_trees =
        [person_a, person_b]
        |> Enum.reject(&is_nil/1)
        |> Enum.map(fn person ->
          case build_ancestor_tree(person.id, depth + 1, graph) do
            nil -> nil
            tree -> %{tree: tree, for_person_id: person.id}
          end
        end)
        |> Enum.reject(&is_nil/1)

      %{
        couple: %{person_a: person_a, person_b: person_b},
        parent_trees: parent_trees
      }
    end
  end
end
