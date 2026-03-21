defmodule Ancestry.Families.MetricsTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Families.Metrics

  # Shared org for all factory-created records in each test
  defp shared_org do
    insert(:organization)
  end

  describe "compute/1 counts" do
    test "empty family returns zero counts and nil metrics" do
      org = shared_org()
      family = insert(:family, organization: org)
      metrics = Metrics.compute(family.id)

      assert metrics.people_count == 0
      assert metrics.photo_count == 0
      assert metrics.generations == nil
      assert metrics.oldest_person == nil
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

  describe "compute/1 oldest_person" do
    test "returns oldest person by birth_year with age (alive)" do
      org = shared_org()
      family = insert(:family, organization: org)
      old = insert(:person, given_name: "Elder", birth_year: 1940, organization: org)
      young = insert(:person, given_name: "Young", birth_year: 1990, organization: org)
      Ancestry.People.add_to_family(old, family)
      Ancestry.People.add_to_family(young, family)

      metrics = Metrics.compute(family.id)
      assert metrics.oldest_person.person.id == old.id
      assert metrics.oldest_person.age == Date.utc_today().year - 1940
    end

    test "returns age at death for deceased person with death_year" do
      org = shared_org()
      family = insert(:family, organization: org)

      deceased =
        insert(:person,
          given_name: "Gone",
          birth_year: 1900,
          death_year: 1980,
          deceased: true,
          organization: org
        )

      Ancestry.People.add_to_family(deceased, family)

      metrics = Metrics.compute(family.id)
      assert metrics.oldest_person.person.id == deceased.id
      assert metrics.oldest_person.age == 80
    end

    test "skips deceased person without death_year, picks next eligible" do
      org = shared_org()
      family = insert(:family, organization: org)

      no_death_year =
        insert(:person,
          given_name: "Unknown",
          birth_year: 1880,
          deceased: true,
          organization: org
        )

      has_death_year =
        insert(:person,
          given_name: "Known",
          birth_year: 1900,
          death_year: 1970,
          deceased: true,
          organization: org
        )

      Ancestry.People.add_to_family(no_death_year, family)
      Ancestry.People.add_to_family(has_death_year, family)

      metrics = Metrics.compute(family.id)
      assert metrics.oldest_person.person.id == has_death_year.id
      assert metrics.oldest_person.age == 70
    end

    test "returns nil when no person has a birth_year" do
      org = shared_org()
      family = insert(:family, organization: org)
      insert(:person, organization: org) |> then(&Ancestry.People.add_to_family(&1, family))

      metrics = Metrics.compute(family.id)
      assert metrics.oldest_person == nil
    end

    test "picks living person with higher age over deceased person born earlier" do
      org = shared_org()
      family = insert(:family, organization: org)

      # Born earlier but died young — age 10
      deceased =
        insert(:person,
          given_name: "Young Death",
          birth_year: 1880,
          death_year: 1890,
          deceased: true,
          organization: org
        )

      # Born later but still alive — age 76+ in 2026
      alive = insert(:person, given_name: "Still Here", birth_year: 1950, organization: org)

      Ancestry.People.add_to_family(deceased, family)
      Ancestry.People.add_to_family(alive, family)

      metrics = Metrics.compute(family.id)
      assert metrics.oldest_person.person.id == alive.id
      assert metrics.oldest_person.age == Date.utc_today().year - 1950
    end

    test "adjusts age for deceased person when death_month < birth_month" do
      org = shared_org()
      family = insert(:family, organization: org)

      deceased =
        insert(:person,
          given_name: "Adjusted",
          birth_year: 1900,
          birth_month: 6,
          death_year: 1980,
          death_month: 3,
          deceased: true,
          organization: org
        )

      Ancestry.People.add_to_family(deceased, family)

      metrics = Metrics.compute(family.id)
      assert metrics.oldest_person.person.id == deceased.id
      assert metrics.oldest_person.age == 79
    end

    test "returns base age for deceased person with nil death_month" do
      org = shared_org()
      family = insert(:family, organization: org)

      deceased =
        insert(:person,
          given_name: "NilMonth",
          birth_year: 1900,
          birth_month: 6,
          death_year: 1980,
          death_month: nil,
          deceased: true,
          organization: org
        )

      Ancestry.People.add_to_family(deceased, family)

      metrics = Metrics.compute(family.id)
      assert metrics.oldest_person.person.id == deceased.id
      assert metrics.oldest_person.age == 80
    end

    test "adjusts age by month when birth_month is available" do
      org = shared_org()
      family = insert(:family, organization: org)
      today = Date.utc_today()
      # Person born in December of a past year — hasn't had birthday this year yet
      person = insert(:person, birth_year: today.year - 50, birth_month: 12, organization: org)
      Ancestry.People.add_to_family(person, family)

      metrics = Metrics.compute(family.id)

      expected_age = if today.month >= 12, do: 50, else: 49
      assert metrics.oldest_person.age == expected_age
    end
  end

  describe "compute/1 generations" do
    test "returns nil when fewer than 2 people" do
      org = shared_org()
      family = insert(:family, organization: org)
      person = insert(:person, organization: org)
      Ancestry.People.add_to_family(person, family)

      metrics = Metrics.compute(family.id)
      assert metrics.generations == nil
    end

    test "3-generation chain returns count 3 with correct root and leaf" do
      org = shared_org()
      family = insert(:family, organization: org)
      grandparent = insert(:person, given_name: "Grand", organization: org)
      parent = insert(:person, given_name: "Parent", organization: org)
      child = insert(:person, given_name: "Child", organization: org)

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
      org = shared_org()
      family = insert(:family, organization: org)
      root = insert(:person, given_name: "Root", organization: org)
      mid = insert(:person, given_name: "Mid", organization: org)
      leaf_short = insert(:person, given_name: "ShortLeaf", organization: org)
      leaf_long = insert(:person, given_name: "LongLeaf", organization: org)

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
      org = shared_org()
      family = insert(:family, organization: org)
      root = insert(:person, given_name: "Root", organization: org)
      child_in = insert(:person, given_name: "InFamily", organization: org)
      child_out = insert(:person, given_name: "OutFamily", organization: org)
      grandchild = insert(:person, given_name: "Grandchild", organization: org)

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
      org = shared_org()
      family = insert(:family, organization: org)
      a = insert(:person, organization: org)
      b = insert(:person, organization: org)
      Ancestry.People.add_to_family(a, family)
      Ancestry.People.add_to_family(b, family)

      metrics = Metrics.compute(family.id)
      assert metrics.generations == nil
    end
  end
end
