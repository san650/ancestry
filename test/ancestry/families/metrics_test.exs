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

    test "picks living person with higher age over deceased person born earlier" do
      family = insert(:family)

      # Born earlier but died young — age 10
      deceased =
        insert(:person,
          given_name: "Young Death",
          birth_year: 1880,
          death_year: 1890,
          deceased: true
        )

      # Born later but still alive — age 76+ in 2026
      alive = insert(:person, given_name: "Still Here", birth_year: 1950)

      Ancestry.People.add_to_family(deceased, family)
      Ancestry.People.add_to_family(alive, family)

      metrics = Metrics.compute(family.id)
      assert metrics.oldest_person.person.id == alive.id
      assert metrics.oldest_person.age == Date.utc_today().year - 1950
    end

    test "adjusts age for deceased person when death_month < birth_month" do
      family = insert(:family)

      deceased =
        insert(:person,
          given_name: "Adjusted",
          birth_year: 1900,
          birth_month: 6,
          death_year: 1980,
          death_month: 3,
          deceased: true
        )

      Ancestry.People.add_to_family(deceased, family)

      metrics = Metrics.compute(family.id)
      assert metrics.oldest_person.person.id == deceased.id
      assert metrics.oldest_person.age == 79
    end

    test "returns base age for deceased person with nil death_month" do
      family = insert(:family)

      deceased =
        insert(:person,
          given_name: "NilMonth",
          birth_year: 1900,
          birth_month: 6,
          death_year: 1980,
          death_month: nil,
          deceased: true
        )

      Ancestry.People.add_to_family(deceased, family)

      metrics = Metrics.compute(family.id)
      assert metrics.oldest_person.person.id == deceased.id
      assert metrics.oldest_person.age == 80
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

  describe "compute/1 generations" do
    test "returns nil when fewer than 2 people" do
      family = insert(:family)
      person = insert(:person)
      Ancestry.People.add_to_family(person, family)

      metrics = Metrics.compute(family.id)
      assert metrics.generations == nil
    end

    test "3-generation chain returns count 3 with correct root and leaf" do
      family = insert(:family)
      grandparent = insert(:person, given_name: "Grand")
      parent = insert(:person, given_name: "Parent")
      child = insert(:person, given_name: "Child")

      Ancestry.People.add_to_family(grandparent, family)
      Ancestry.People.add_to_family(parent, family)
      Ancestry.People.add_to_family(child, family)

      {:ok, _} =
        Ancestry.Relationships.create_relationship(grandparent, parent, "parent", %{
          role: "father"
        })

      {:ok, _} =
        Ancestry.Relationships.create_relationship(parent, child, "parent", %{role: "father"})

      metrics = Metrics.compute(family.id)
      assert metrics.generations.count == 3
      assert metrics.generations.root.id == grandparent.id
      assert metrics.generations.leaf.id == child.id
    end

    test "picks the longest branch when multiple exist" do
      family = insert(:family)
      root = insert(:person, given_name: "Root")
      mid = insert(:person, given_name: "Mid")
      leaf_short = insert(:person, given_name: "ShortLeaf")
      leaf_long = insert(:person, given_name: "LongLeaf")

      for p <- [root, mid, leaf_short, leaf_long], do: Ancestry.People.add_to_family(p, family)

      {:ok, _} =
        Ancestry.Relationships.create_relationship(root, mid, "parent", %{role: "father"})

      {:ok, _} =
        Ancestry.Relationships.create_relationship(root, leaf_short, "parent", %{role: "father"})

      {:ok, _} =
        Ancestry.Relationships.create_relationship(mid, leaf_long, "parent", %{role: "father"})

      metrics = Metrics.compute(family.id)
      assert metrics.generations.count == 3
      assert metrics.generations.root.id == root.id
      assert metrics.generations.leaf.id == leaf_long.id
    end

    test "scopes to family members only — ignores children outside the family" do
      family = insert(:family)
      root = insert(:person, given_name: "Root")
      child_in = insert(:person, given_name: "InFamily")
      child_out = insert(:person, given_name: "OutFamily")
      grandchild = insert(:person, given_name: "Grandchild")

      Ancestry.People.add_to_family(root, family)
      Ancestry.People.add_to_family(child_in, family)
      # child_out is NOT added to family
      Ancestry.People.add_to_family(grandchild, family)

      {:ok, _} =
        Ancestry.Relationships.create_relationship(root, child_in, "parent", %{role: "father"})

      {:ok, _} =
        Ancestry.Relationships.create_relationship(root, child_out, "parent", %{role: "father"})

      {:ok, _} =
        Ancestry.Relationships.create_relationship(child_out, grandchild, "parent", %{
          role: "father"
        })

      metrics = Metrics.compute(family.id)
      # root -> child_in is 2 generations
      # root -> child_out -> grandchild would be 3, but child_out is not in family so chain breaks
      assert metrics.generations.count == 2
      assert metrics.generations.root.id == root.id
      assert metrics.generations.leaf.id == child_in.id
    end

    test "returns nil when people exist but no parent relationships" do
      family = insert(:family)
      a = insert(:person)
      b = insert(:person)
      Ancestry.People.add_to_family(a, family)
      Ancestry.People.add_to_family(b, family)

      metrics = Metrics.compute(family.id)
      assert metrics.generations == nil
    end
  end
end
