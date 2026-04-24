defmodule Ancestry.Families.MetricsTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Families.Metrics

  # Shared org for all factory-created records in each test
  defp shared_org do
    insert(:organization)
  end

  describe "compute/1 counts" do
    test "empty family returns zero counts" do
      org = shared_org()
      family = insert(:family, organization: org)
      metrics = Metrics.compute(family.id)

      assert metrics.people_count == 0
      assert metrics.photo_count == 0
    end

    test "counts people in the family" do
      org = shared_org()
      family = insert(:family, organization: org)
      person_a = insert(:person, organization: org)
      person_b = insert(:person, organization: org)
      Ancestry.People.add_to_family(person_a, family)
      Ancestry.People.add_to_family(person_b, family)

      metrics = Metrics.compute(family.id)
      assert metrics.people_count == 2
    end

    test "counts photos across all galleries in the family" do
      org = shared_org()
      family = insert(:family, organization: org)
      gallery_a = insert(:gallery, family: family)
      gallery_b = insert(:gallery, family: family)
      insert(:photo, gallery: gallery_a)
      insert(:photo, gallery: gallery_a)
      insert(:photo, gallery: gallery_b)

      metrics = Metrics.compute(family.id)
      assert metrics.photo_count == 3
    end

    test "does not count photos from other families" do
      org = shared_org()
      family = insert(:family, organization: org)
      other_family = insert(:family, organization: org)
      gallery = insert(:gallery, family: family)
      other_gallery = insert(:gallery, family: other_family)
      insert(:photo, gallery: gallery)
      insert(:photo, gallery: other_gallery)

      metrics = Metrics.compute(family.id)
      assert metrics.photo_count == 1
    end
  end
end
