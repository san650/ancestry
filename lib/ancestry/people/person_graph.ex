defmodule Ancestry.People.PersonGraph do
  @moduledoc """
  Builds a person-centered family tree with N generations of ancestors
  above and N generations of descendants below a focus person.

  Threads a visited map (%{person_id => generation}) through all recursive
  calls to detect cycles. When a person already in the map is encountered,
  they are marked `duplicated: true` and no further ancestry is built above them.
  """

  alias Ancestry.People.FamilyGraph
  alias Ancestry.People.Person

  @default_opts [ancestors: 2, descendants: 1, other: 0]

  defstruct [:focus_person, :ancestors, :center, :descendants, :family_id]

  @doc """
  Builds a person-centered tree. Accepts a family_id (builds graph internally)
  or a pre-built %FamilyGraph{} (zero queries). Optionally accepts opts:

    - `ancestors:` — how many generations upward to show (default 2)
    - `descendants:` — how many generations downward to show (default 1)
    - `other:` — accepted but currently unused (default 0)
  """
  def build(focus_person, graph_or_id), do: build(focus_person, graph_or_id, [])

  def build(%Person{} = focus_person, family_id, opts) when is_integer(family_id) do
    build(focus_person, FamilyGraph.for_family(family_id), opts)
  end

  def build(%Person{} = focus_person, %FamilyGraph{} = graph, opts) do
    opts = Keyword.merge(@default_opts, opts)
    max_ancestors = opts[:ancestors]
    max_descendants = opts[:descendants]

    visited = %{focus_person.id => 0}

    {ancestor_tree, visited} =
      build_ancestor_tree(focus_person.id, 1, max_ancestors, graph, visited)

    {center, _visited} =
      build_family_unit_full(focus_person, 0, max_descendants, graph, visited)

    %__MODULE__{
      focus_person: focus_person,
      ancestors: ancestor_tree,
      center: center,
      family_id: graph.family_id
    }
  end

  # --- Center Row ---

  defp build_family_unit_full(person, depth, max_descendants, %FamilyGraph{} = graph, visited) do
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

    # Children with current partner
    {partner_children, visited} =
      if partner do
        FamilyGraph.children_of_pair(graph, person.id, partner.id)
        |> build_child_units_acc(depth, max_descendants, graph, visited)
      else
        {[], visited}
      end

    # Children with each previous (non-ex) partner
    {previous_partner_groups, visited} =
      Enum.reduce(previous, {[], visited}, fn {prev, _rel}, {groups, vis} ->
        {children, vis} =
          FamilyGraph.children_of_pair(graph, person.id, prev.id)
          |> build_child_units_acc(depth, max_descendants, graph, vis)

        {groups ++ [%{person: prev, children: children}], vis}
      end)

    # Children with each ex-partner
    {ex_partner_groups, visited} =
      Enum.reduce(ex_partners, {[], visited}, fn {ex, _rel}, {groups, vis} ->
        {children, vis} =
          FamilyGraph.children_of_pair(graph, person.id, ex.id)
          |> build_child_units_acc(depth, max_descendants, graph, vis)

        {groups ++ [%{person: ex, children: children}], vis}
      end)

    # Solo children (no co-parent)
    {solo_children, visited} =
      FamilyGraph.solo_children(graph, person.id)
      |> build_child_units_acc(depth, max_descendants, graph, visited)

    result = %{
      focus: person,
      partner: partner,
      previous_partners: previous_partner_groups,
      ex_partners: ex_partner_groups,
      partner_children: partner_children,
      solo_children: solo_children
    }

    {result, visited}
  end

  defp build_child_units_acc(children, depth, max_descendants, graph, visited) do
    if depth >= max_descendants do
      {[], visited}
    else
      at_limit = depth + 1 >= max_descendants

      Enum.reduce(children, {[], visited}, fn child, {units, vis} ->
        if Map.has_key?(vis, child.id) do
          # Duplicated child — stub
          {units ++ [%{person: child, duplicated: true, has_more: false, children: nil}], vis}
        else
          vis = Map.put(vis, child.id, -(depth + 1))

          if at_limit do
            has_more = FamilyGraph.has_children?(graph, child.id)
            partners = FamilyGraph.active_partners(graph, child.id)

            partner =
              case partners do
                [{p, _} | _] -> p
                [] -> nil
              end

            {units ++ [%{person: child, partner: partner, has_more: has_more, children: nil}],
             vis}
          else
            {unit, vis} = build_family_unit_full(child, depth + 1, max_descendants, graph, vis)

            has_children =
              unit.partner_children != [] or unit.solo_children != [] or unit.ex_partners != []

            unit = Map.put(unit, :has_more, false) |> Map.put(:has_children, has_children)
            {units ++ [unit], vis}
          end
        end
      end)
    end
  end

  # --- Ancestors (recursive tree) ---

  defp build_ancestor_tree(_person_id, generation, max_ancestors, _graph, visited)
       when generation > max_ancestors do
    {nil, visited}
  end

  defp build_ancestor_tree(person_id, generation, max_ancestors, graph, visited) do
    parents = FamilyGraph.parents(graph, person_id)

    parents =
      if generation == 1 do
        sort_by_depth(parents, graph)
      else
        parents
      end

    case parents do
      [] ->
        {nil, visited}

      _ ->
        {person_a_raw, person_b_raw} =
          case parents do
            [{p, _}] -> {p, nil}
            [{p1, _}, {p2, _} | _] -> {p1, p2}
          end

        # Check visited, wrap with duplicated flag
        {person_a_entry, visited} = check_and_mark(person_a_raw, generation, visited)

        {person_b_entry, visited} =
          if person_b_raw,
            do: check_and_mark(person_b_raw, generation, visited),
            else: {nil, visited}

        # Build parent_trees ONLY for non-duplicated persons
        {parent_trees, visited} =
          [person_a_entry, person_b_entry]
          |> Enum.reject(&is_nil/1)
          |> Enum.reject(& &1.duplicated)
          |> Enum.reduce({[], visited}, fn entry, {trees, vis} ->
            case build_ancestor_tree(
                   entry.person.id,
                   generation + 1,
                   max_ancestors,
                   graph,
                   vis
                 ) do
              {nil, vis} -> {trees, vis}
              {tree, vis} -> {trees ++ [%{tree: tree, for_person_id: entry.person.id}], vis}
            end
          end)

        node = %{
          couple: %{person_a: person_a_entry, person_b: person_b_entry},
          parent_trees: parent_trees
        }

        {node, visited}
    end
  end

  defp check_and_mark(person, generation, visited) do
    if Map.has_key?(visited, person.id) do
      {%{person: person, duplicated: true}, visited}
    else
      {%{person: person, duplicated: false}, Map.put(visited, person.id, generation)}
    end
  end

  defp sort_by_depth(parents, graph) do
    Enum.sort_by(parents, fn {p, _rel} -> max_ancestor_depth(p.id, graph) end, :desc)
  end

  defp max_ancestor_depth(person_id, graph, seen \\ MapSet.new()) do
    if MapSet.member?(seen, person_id) do
      0
    else
      seen = MapSet.put(seen, person_id)

      case FamilyGraph.parents(graph, person_id) do
        [] ->
          0

        parents ->
          parents
          |> Enum.map(fn {p, _rel} -> 1 + max_ancestor_depth(p.id, graph, seen) end)
          |> Enum.max()
      end
    end
  end
end
