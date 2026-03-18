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

  describe "compute/1 oldest_person" do
    test "returns oldest person by birth_year with age (alive)" do
      family = insert(:family)
      old = insert(:person, given_name: "Elder", birth_year: 1940)
      young = insert(:person, given_name: "Young", birth_year: 1990)
      Ancestry.People.add_to_family(old, family)
      Ancestry.People.add_to_family(young, family)

      metrics = Metrics.compute(family.id)
      assert metrics.oldest_person.person.id == old.id
      assert metrics.oldest_person.age == Date.utc_today().year - 1940
    end

    test "returns age at death for deceased person with death_year" do
      family = insert(:family)

      deceased =
        insert(:person, given_name: "Gone", birth_year: 1900, death_year: 1980, deceased: true)

      Ancestry.People.add_to_family(deceased, family)

      metrics = Metrics.compute(family.id)
      assert metrics.oldest_person.person.id == deceased.id
      assert metrics.oldest_person.age == 80
    end

    test "skips deceased person without death_year, picks next eligible" do
      family = insert(:family)
      no_death_year = insert(:person, given_name: "Unknown", birth_year: 1880, deceased: true)

      has_death_year =
        insert(:person, given_name: "Known", birth_year: 1900, death_year: 1970, deceased: true)

      Ancestry.People.add_to_family(no_death_year, family)
      Ancestry.People.add_to_family(has_death_year, family)

      metrics = Metrics.compute(family.id)
      assert metrics.oldest_person.person.id == has_death_year.id
      assert metrics.oldest_person.age == 70
    end

    test "returns nil when no person has a birth_year" do
      family = insert(:family)
      insert(:person) |> then(&Ancestry.People.add_to_family(&1, family))

      metrics = Metrics.compute(family.id)
      assert metrics.oldest_person == nil
    end

    test "adjusts age by month when birth_month is available" do
      family = insert(:family)
      today = Date.utc_today()
      # Person born in December of a past year — hasn't had birthday this year yet
      person = insert(:person, birth_year: today.year - 50, birth_month: 12)
      Ancestry.People.add_to_family(person, family)

      metrics = Metrics.compute(family.id)

      expected_age = if today.month >= 12, do: 50, else: 49
      assert metrics.oldest_person.age == expected_age
    end
  end
end
