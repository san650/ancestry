defmodule Ancestry.Families.MetricsTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Families.Metrics

  describe "compute/1 counts" do
    test "empty family returns zero counts and nil metrics" do
      family = insert(:family)
      metrics = Metrics.compute(family.id)

      assert metrics.people_count == 0
      assert metrics.photo_count == 0
      assert metrics.generations == nil
      assert metrics.oldest_person == nil
    end

    test "counts people in the family" do
      family = insert(:family)
      person_a = insert(:person)
      person_b = insert(:person)
      Ancestry.People.add_to_family(person_a, family)
      Ancestry.People.add_to_family(person_b, family)

      metrics = Metrics.compute(family.id)
      assert metrics.people_count == 2
    end

    test "counts photos across all galleries in the family" do
      family = insert(:family)
      gallery_a = insert(:gallery, family: family)
      gallery_b = insert(:gallery, family: family)
      insert(:photo, gallery: gallery_a)
      insert(:photo, gallery: gallery_a)
      insert(:photo, gallery: gallery_b)

      metrics = Metrics.compute(family.id)
      assert metrics.photo_count == 3
    end

    test "does not count photos from other families" do
      family = insert(:family)
      other_family = insert(:family)
      gallery = insert(:gallery, family: family)
      other_gallery = insert(:gallery, family: other_family)
      insert(:photo, gallery: gallery)
      insert(:photo, gallery: other_gallery)

      metrics = Metrics.compute(family.id)
      assert metrics.photo_count == 1
    end
  end
end
