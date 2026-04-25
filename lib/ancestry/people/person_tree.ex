defmodule Ancestry.People.PersonTree do
  @moduledoc """
  Builds a nested tree structure from a FamilyGraph for the interactive tree view.

  Similar to `PrintTree` but includes additional UI-relevant flags on each entry:
  `has_more_up`, `has_more_down`, and `duplicated`. These allow the tree view
  component to render expansion indicators and duplicate markers on person cards.
  """

  alias Ancestry.People.FamilyGraph
  alias Ancestry.People.Person

  defstruct [:focus_person_id, :roots]

  @doc """
  Builds an interactive tree centered on the focus person.

  Options:
    - `ancestors:` — generations upward (default 2)
    - `descendants:` — generations downward from focus (default 2)
    - `other:` — lateral expansion depth (default 1)
  """
  def build(%Person{} = focus_person, %FamilyGraph{} = graph, opts \\ []) do
    ancestors = Keyword.get(opts, :ancestors, 2)
    descendants = Keyword.get(opts, :descendants, 2)
    other = Keyword.get(opts, :other, 1)

    # Find the root ancestors by walking up from the focus person.
    # Returns {root_id, has_more_up} tuples.
    root_tuples = find_roots(graph, focus_person.id, ancestors)

    # Build the tree downward from each root
    seen = MapSet.new()

    {tree_roots, _seen} =
      Enum.map_reduce(root_tuples, seen, fn {root_id, has_more_up}, seen ->
        build_person_entry(
          graph,
          root_id,
          focus_person.id,
          seen,
          descendants,
          other,
          0,
          ancestors,
          has_more_up
        )
      end)

    %__MODULE__{focus_person_id: focus_person.id, roots: tree_roots}
  end

  # Walk upward from the focus person to find the oldest ancestors within depth.
  # Returns a list of {person_id, has_more_up} tuples.
  defp find_roots(graph, person_id, max_depth) do
    do_find_roots(graph, [{person_id, false}], 0, max_depth, MapSet.new())
  end

  defp do_find_roots(graph, person_tuples, depth, max_depth, _visited)
       when depth >= max_depth do
    # At the depth limit — check if each person has parents beyond the boundary
    Enum.map(person_tuples, fn {pid, _} ->
      has_more = FamilyGraph.parents(graph, pid) != []
      {pid, has_more}
    end)
  end

  defp do_find_roots(graph, person_tuples, depth, max_depth, visited) do
    {roots, next_level, visited} =
      Enum.reduce(person_tuples, {[], [], visited}, fn {pid, _}, {roots_acc, next_acc, vis} ->
        if MapSet.member?(vis, pid) do
          {roots_acc, next_acc, vis}
        else
          vis = MapSet.put(vis, pid)
          parents = FamilyGraph.parents(graph, pid)
          parent_ids = Enum.map(parents, fn {p, _r} -> p.id end)

          if parent_ids == [] do
            # No parents — this is a true root, no more ancestors above
            {[{pid, false} | roots_acc], next_acc, vis}
          else
            next_tuples = Enum.map(parent_ids, fn id -> {id, false} end)
            {roots_acc, next_tuples ++ next_acc, vis}
          end
        end
      end)

    if next_level == [] do
      Enum.reverse(roots)
    else
      unique_next = next_level |> Enum.uniq_by(fn {id, _} -> id end)

      upper_roots =
        do_find_roots(graph, unique_next, depth + 1, max_depth, visited)

      Enum.reverse(roots) ++ upper_roots
    end
  end

  defp build_person_entry(
         graph,
         person_id,
         focus_id,
         seen,
         max_desc,
         max_other,
         depth_from_focus,
         max_ancestors,
         has_more_up
       ) do
    if MapSet.member?(seen, person_id) do
      person = FamilyGraph.fetch_person!(graph, person_id)

      entry = %{
        type: :person,
        person: person,
        is_focus: person_id == focus_id,
        partners: [],
        solo_children: [],
        has_more_up: FamilyGraph.parents(graph, person_id) != [],
        has_more_down: FamilyGraph.has_children?(graph, person_id),
        duplicated: true
      }

      {entry, seen}
    else
      person = FamilyGraph.fetch_person!(graph, person_id)
      seen = MapSet.put(seen, person_id)
      is_focus = person_id == focus_id

      on_direct_path = is_ancestor_of_focus?(graph, person_id, focus_id, max_ancestors)

      all_partners = FamilyGraph.all_partners(graph, person_id)
      solo_children = FamilyGraph.solo_children(graph, person_id)

      expand_children? =
        should_expand_children?(
          is_focus,
          on_direct_path,
          depth_from_focus,
          max_desc,
          max_other
        )

      {partner_entries, seen} =
        Enum.map_reduce(all_partners, seen, fn {partner, rel}, seen ->
          shared_children = FamilyGraph.children_of_pair(graph, person_id, partner.id)

          {children_entries, seen} =
            if expand_children? do
              Enum.map_reduce(shared_children, seen, fn child, seen ->
                child_depth = if is_focus, do: 1, else: depth_from_focus + 1

                build_person_entry(
                  graph,
                  child.id,
                  focus_id,
                  seen,
                  max_desc,
                  max_other,
                  child_depth,
                  max_ancestors,
                  false
                )
              end)
            else
              {[], seen}
            end

          partner_has_more_up = FamilyGraph.parents(graph, partner.id) != []

          entry = %{
            type: :partner,
            person: partner,
            relationship_type: rel.type,
            children: children_entries,
            has_more_up: partner_has_more_up
          }

          {entry, seen}
        end)

      {solo_entries, seen} =
        if expand_children? do
          Enum.map_reduce(solo_children, seen, fn child, seen ->
            child_depth = if is_focus, do: 1, else: depth_from_focus + 1

            build_person_entry(
              graph,
              child.id,
              focus_id,
              seen,
              max_desc,
              max_other,
              child_depth,
              max_ancestors,
              false
            )
          end)
        else
          {[], seen}
        end

      has_more_down =
        if expand_children? do
          false
        else
          FamilyGraph.has_children?(graph, person_id)
        end

      entry = %{
        type: :person,
        person: person,
        is_focus: is_focus,
        partners: partner_entries,
        solo_children: solo_entries,
        has_more_up: has_more_up,
        has_more_down: has_more_down,
        duplicated: false
      }

      {entry, seen}
    end
  end

  defp should_expand_children?(true, _on_direct, _depth, _max_desc, _max_other), do: true
  defp should_expand_children?(_is_focus, true, _depth, _max_desc, _max_other), do: true

  defp should_expand_children?(_is_focus, _on_direct, depth, max_desc, _max_other)
       when depth < max_desc,
       do: true

  defp should_expand_children?(_, _, _, _, _), do: false

  defp is_ancestor_of_focus?(graph, person_id, focus_id, max_depth) do
    person_id == focus_id or do_is_ancestor?(graph, focus_id, person_id, 0, max_depth)
  end

  defp do_is_ancestor?(_graph, _current_id, _target_id, depth, max_depth) when depth >= max_depth,
    do: false

  defp do_is_ancestor?(graph, current_id, target_id, depth, max_depth) do
    parents = FamilyGraph.parents(graph, current_id)

    Enum.any?(parents, fn {parent, _rel} ->
      parent.id == target_id or do_is_ancestor?(graph, parent.id, target_id, depth + 1, max_depth)
    end)
  end
end
