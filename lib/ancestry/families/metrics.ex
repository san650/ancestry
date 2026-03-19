defmodule Ancestry.Families.Metrics do
  import Ecto.Query

  alias Ancestry.Repo
  alias Ancestry.People.FamilyMember
  alias Ancestry.People.Person
  alias Ancestry.Galleries.Gallery
  alias Ancestry.Galleries.Photo
  alias Ancestry.Relationships.Relationship

  def compute(family_id) do
    %{
      people_count: count_people(family_id),
      photo_count: count_photos(family_id),
      generations: find_longest_line(family_id),
      oldest_person: find_oldest_person(family_id)
    }
  end

  defp count_people(family_id) do
    Repo.one(
      from fm in FamilyMember,
        where: fm.family_id == ^family_id,
        select: count(fm.id)
    )
  end

  defp count_photos(family_id) do
    Repo.one(
      from p in Photo,
        join: g in Gallery,
        on: g.id == p.gallery_id,
        where: g.family_id == ^family_id,
        select: count(p.id)
    )
  end

  defp find_oldest_person(family_id) do
    family_member_ids = family_member_ids_query(family_id)

    candidates =
      Repo.all(
        from p in Person,
          where: p.id in subquery(family_member_ids),
          where: not is_nil(p.birth_year),
          where: p.deceased == false or (p.deceased == true and not is_nil(p.death_year)),
          order_by: [
            asc: p.birth_year,
            asc_nulls_last: p.birth_month,
            asc_nulls_last: p.birth_day
          ],
          limit: 1
      )

    case candidates do
      [person] ->
        age = calculate_age(person)
        %{person: person, age: age}

      [] ->
        nil
    end
  end

  defp calculate_age(%Person{deceased: true, birth_year: by, death_year: dy} = p) do
    base = dy - by
    adjust_age(base, p.birth_month, p.birth_day, p.death_month, p.death_day)
  end

  defp calculate_age(%Person{birth_year: by} = p) do
    today = Date.utc_today()
    base = today.year - by
    adjust_age(base, p.birth_month, p.birth_day, today.month, today.day)
  end

  defp adjust_age(base, _bm, _bd, nil, _ed), do: base
  defp adjust_age(base, nil, _bd, _em, _ed), do: base

  defp adjust_age(base, bm, bd, end_month, end_day) do
    bd = bd || 1
    end_day = end_day || 1
    if {end_month, end_day} < {bm, bd}, do: base - 1, else: base
  end

  defp find_longest_line(family_id) do
    member_ids = MapSet.new(Repo.all(family_member_ids_query(family_id)))

    if MapSet.size(member_ids) < 2 do
      nil
    else
      member_id_list = MapSet.to_list(member_ids)

      parent_child_pairs =
        Repo.all(
          from r in Relationship,
            where: r.type == "parent",
            where: r.person_a_id in ^member_id_list,
            where: r.person_b_id in ^member_id_list,
            select: {r.person_a_id, r.person_b_id}
        )

      if parent_child_pairs == [] do
        nil
      else
        children_map =
          Enum.group_by(parent_child_pairs, fn {parent_id, _} -> parent_id end, fn {_, child_id} ->
            child_id
          end)

        child_set = MapSet.new(parent_child_pairs, fn {_, child_id} -> child_id end)

        # Root ancestors: family members who have children but are not children themselves (within family)
        roots =
          member_ids
          |> Enum.filter(&Map.has_key?(children_map, &1))
          |> Enum.reject(&MapSet.member?(child_set, &1))

        if roots == [] do
          nil
        else
          {best_count, best_root_id, best_leaf_id} =
            Enum.reduce(roots, {0, nil, nil}, fn root_id, best ->
              {depth, leaf_id} = dfs_longest(root_id, children_map)
              if depth > elem(best, 0), do: {depth, root_id, leaf_id}, else: best
            end)

          if best_count >= 2 do
            people_by_id = load_people_by_ids([best_root_id, best_leaf_id])

            %{
              count: best_count,
              root: Map.get(people_by_id, best_root_id),
              leaf: Map.get(people_by_id, best_leaf_id)
            }
          else
            nil
          end
        end
      end
    end
  end

  defp dfs_longest(person_id, children_map) do
    case Map.get(children_map, person_id, []) do
      [] ->
        {1, person_id}

      children ->
        children
        |> Enum.map(fn child_id -> dfs_longest(child_id, children_map) end)
        |> Enum.max_by(fn {depth, _} -> depth end)
        |> then(fn {depth, leaf_id} -> {depth + 1, leaf_id} end)
    end
  end

  defp load_people_by_ids(ids) do
    ids = Enum.uniq(ids)

    Repo.all(from p in Person, where: p.id in ^ids)
    |> Map.new(fn p -> {p.id, p} end)
  end

  defp family_member_ids_query(family_id) do
    from fm in FamilyMember,
      where: fm.family_id == ^family_id,
      select: fm.person_id
  end
end
