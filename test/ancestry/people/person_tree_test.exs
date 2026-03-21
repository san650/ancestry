defmodule Ancestry.People.PersonTreeTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.People
  alias Ancestry.People.PersonTree
  alias Ancestry.Relationships

  describe "build/2 with family_id" do
    test "only includes people from the specified family" do
      family1 = family_fixture(%{name: "Family 1"})
      family2 = family_fixture(%{name: "Family 2"})

      # Shared person — member of both families
      {:ok, person} = People.create_person(family1, %{given_name: "Shared", surname: "Person"})
      People.add_to_family(person, family2)

      # Family 1 relatives
      {:ok, f1_parent} = People.create_person(family1, %{given_name: "F1Dad", surname: "D"})
      {:ok, f1_child} = People.create_person(family1, %{given_name: "F1Kid", surname: "D"})

      # Family 2 relatives
      {:ok, f2_parent} = People.create_person(family2, %{given_name: "F2Dad", surname: "D"})
      {:ok, f2_child} = People.create_person(family2, %{given_name: "F2Kid", surname: "D"})

      # Create relationships
      {:ok, _} = Relationships.create_relationship(f1_parent, person, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(f2_parent, person, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(person, f1_child, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(person, f2_child, "parent", %{role: "father"})

      # Build tree scoped to family 1
      tree = PersonTree.build(person, family1.id)

      # Ancestors should only have f1_parent
      assert tree.ancestors != nil
      assert tree.ancestors.couple.person_a.id == f1_parent.id
      assert tree.ancestors.couple.person_b == nil

      # Descendants (solo_children) should only have f1_child
      assert length(tree.center.solo_children) == 1
      assert hd(tree.center.solo_children).focus.id == f1_child.id
    end

    test "build/1 without family_id returns all relatives (backwards compat)" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "Person", surname: "P"})
      {:ok, parent} = People.create_person(family, %{given_name: "Parent", surname: "P"})
      {:ok, _} = Relationships.create_relationship(parent, person, "parent", %{role: "father"})

      tree = PersonTree.build(person)
      assert tree.ancestors != nil
      assert tree.ancestors.couple.person_a.id == parent.id
    end
  end

  describe "multiple current partners (widowed and remarried)" do
    test "latest partner by marriage year is main partner, others are previous partners" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "John", surname: "Doe"})

      {:ok, first_wife} =
        People.create_person(family, %{given_name: "Jane", surname: "Doe", deceased: true})

      {:ok, second_wife} =
        People.create_person(family, %{given_name: "Mary", surname: "Doe"})

      # First marriage (1985) — wife later died
      {:ok, _} =
        Relationships.create_relationship(person, first_wife, "married", %{marriage_year: 1985})

      # Second marriage (1995)
      {:ok, _} =
        Relationships.create_relationship(person, second_wife, "married", %{marriage_year: 1995})

      # Child with first wife
      {:ok, child1} = People.create_person(family, %{given_name: "Kid1", surname: "Doe"})
      {:ok, _} = Relationships.create_relationship(person, child1, "parent", %{role: "father"})

      {:ok, _} =
        Relationships.create_relationship(first_wife, child1, "parent", %{role: "mother"})

      # Child with second wife
      {:ok, child2} = People.create_person(family, %{given_name: "Kid2", surname: "Doe"})
      {:ok, _} = Relationships.create_relationship(person, child2, "parent", %{role: "father"})

      {:ok, _} =
        Relationships.create_relationship(second_wife, child2, "parent", %{role: "mother"})

      tree = PersonTree.build(person, family.id)

      # Latest partner (second wife, married 1995) should be the main partner
      assert tree.center.partner.id == second_wife.id

      # First wife should be in previous_partners
      assert length(tree.center.previous_partners) == 1
      [prev] = tree.center.previous_partners
      assert prev.person.id == first_wife.id

      # Children grouped correctly
      assert length(tree.center.partner_children) == 1
      assert hd(tree.center.partner_children).focus.id == child2.id

      assert length(prev.children) == 1
      assert hd(prev.children).focus.id == child1.id
    end

    test "falls back to person id when no marriage dates" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "John", surname: "Doe"})
      {:ok, first_wife} = People.create_person(family, %{given_name: "Jane", surname: "Doe"})
      {:ok, second_wife} = People.create_person(family, %{given_name: "Mary", surname: "Doe"})

      # No marriage dates
      {:ok, _} = Relationships.create_relationship(person, first_wife, "married", %{})
      {:ok, _} = Relationships.create_relationship(person, second_wife, "married", %{})

      tree = PersonTree.build(person, family.id)

      # Higher person.id should be the main partner (latest added)
      latest = Enum.max_by([first_wife, second_wife], & &1.id)
      earlier = Enum.min_by([first_wife, second_wife], & &1.id)

      assert tree.center.partner.id == latest.id
      assert length(tree.center.previous_partners) == 1
      assert hd(tree.center.previous_partners).person.id == earlier.id
    end

    test "single partner produces no previous_partners" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "John", surname: "Doe"})
      {:ok, wife} = People.create_person(family, %{given_name: "Jane", surname: "Doe"})

      {:ok, _} = Relationships.create_relationship(person, wife, "married", %{})

      tree = PersonTree.build(person, family.id)

      assert tree.center.partner.id == wife.id
      assert tree.center.previous_partners == []
    end

    test "no partners produces nil partner and empty previous_partners" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "John", surname: "Doe"})

      tree = PersonTree.build(person, family.id)

      assert tree.center.partner == nil
      assert tree.center.previous_partners == []
    end
  end

  defp family_fixture(attrs \\ %{}) do
    {:ok, family} =
      attrs
      |> Enum.into(%{name: "Test Family"})
      |> Ancestry.Families.create_family()

    family
  end
end
