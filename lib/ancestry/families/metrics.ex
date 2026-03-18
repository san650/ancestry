defmodule Ancestry.Families.Metrics do
  import Ecto.Query

  alias Ancestry.Repo
  alias Ancestry.People.FamilyMember
  alias Ancestry.Galleries.Gallery
  alias Ancestry.Galleries.Photo

  def compute(family_id) do
    %{
      people_count: count_people(family_id),
      photo_count: count_photos(family_id),
      generations: nil,
      oldest_person: nil
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
end
