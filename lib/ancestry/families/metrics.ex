defmodule Ancestry.Families.Metrics do
  import Ecto.Query

  alias Ancestry.Repo
  alias Ancestry.People.FamilyMember
  alias Ancestry.People.Person
  alias Ancestry.Galleries.Gallery
  alias Ancestry.Galleries.Photo

  def compute(family_id) do
    %{
      people_count: count_people(family_id),
      photo_count: count_photos(family_id),
      generations: nil,
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

  defp adjust_age(base, nil, _bd, _em, _ed), do: base

  defp adjust_age(base, bm, bd, end_month, end_day) do
    bd = bd || 1
    end_day = end_day || 1
    if {end_month, end_day} < {bm, bd}, do: base - 1, else: base
  end

  defp family_member_ids_query(family_id) do
    from fm in FamilyMember,
      where: fm.family_id == ^family_id,
      select: fm.person_id
  end
end
