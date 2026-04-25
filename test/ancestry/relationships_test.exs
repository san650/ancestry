defmodule Ancestry.RelationshipsTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Relationships
  alias Ancestry.Relationships.Relationship
  alias Ancestry.People

  describe "relationship changeset" do
    test "valid parent changeset" do
      changeset =
        Relationship.changeset(%Relationship{}, %{
          person_a_id: 1,
          person_b_id: 2,
          type: "parent",
          metadata: %{__type__: "parent", role: "father"}
        })

      assert changeset.valid?
    end

    test "valid partner changeset with symmetric ID ordering" do
      changeset =
        Relationship.changeset(%Relationship{}, %{
          person_a_id: 5,
          person_b_id: 3,
          type: "married",
          metadata: %{__type__: "married", marriage_year: 1920}
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :person_a_id) == 3
      assert Ecto.Changeset.get_field(changeset, :person_b_id) == 5
    end

    test "rejects invalid type" do
      changeset =
        Relationship.changeset(%Relationship{}, %{
          person_a_id: 1,
          person_b_id: 2,
          type: "cousin"
        })

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).type
    end

    test "rejects same person on both sides" do
      changeset =
        Relationship.changeset(%Relationship{}, %{
          person_a_id: 1,
          person_b_id: 1,
          type: "married"
        })

      refute changeset.valid?
      assert "cannot be the same person" in errors_on(changeset).person_b_id
    end

    test "parent type requires role in metadata" do
      changeset =
        Relationship.changeset(%Relationship{}, %{
          person_a_id: 1,
          person_b_id: 2,
          type: "parent",
          metadata: %{__type__: "parent"}
        })

      refute changeset.valid?
    end
  end

  describe "create_relationship/4" do
    test "creates a parent relationship" do
      family = family_fixture()
      {:ok, parent} = People.create_person(family, %{given_name: "John", surname: "Doe"})
      {:ok, child} = People.create_person(family, %{given_name: "Jane", surname: "Doe"})

      assert {:ok, rel} =
               Relationships.create_relationship(parent, child, "parent", %{role: "father"})

      assert rel.person_a_id == parent.id
      assert rel.person_b_id == child.id
      assert rel.type == "parent"
    end

    test "creates a partner relationship with symmetric ordering" do
      family = family_fixture()
      {:ok, person_a} = People.create_person(family, %{given_name: "Alice", surname: "A"})
      {:ok, person_b} = People.create_person(family, %{given_name: "Bob", surname: "B"})

      assert {:ok, rel} =
               Relationships.create_relationship(person_b, person_a, "married", %{
                 marriage_year: 2020
               })

      assert rel.person_a_id == min(person_a.id, person_b.id)
      assert rel.person_b_id == max(person_a.id, person_b.id)
    end

    test "prevents duplicate relationships" do
      family = family_fixture()
      {:ok, parent} = People.create_person(family, %{given_name: "John", surname: "Doe"})
      {:ok, child} = People.create_person(family, %{given_name: "Jane", surname: "Doe"})

      assert {:ok, _} =
               Relationships.create_relationship(parent, child, "parent", %{role: "father"})

      assert {:error, _} =
               Relationships.create_relationship(parent, child, "parent", %{role: "father"})
    end

    test "enforces max 2 parents per child" do
      family = family_fixture()
      {:ok, father} = People.create_person(family, %{given_name: "John", surname: "D"})
      {:ok, mother} = People.create_person(family, %{given_name: "Jane", surname: "D"})
      {:ok, extra} = People.create_person(family, %{given_name: "Extra", surname: "D"})
      {:ok, child} = People.create_person(family, %{given_name: "Kid", surname: "D"})

      assert {:ok, _} =
               Relationships.create_relationship(father, child, "parent", %{role: "father"})

      assert {:ok, _} =
               Relationships.create_relationship(mother, child, "parent", %{role: "mother"})

      assert {:error, :max_parents_reached} =
               Relationships.create_relationship(extra, child, "parent", %{role: "father"})
    end
  end

  describe "delete_relationship/1" do
    test "deletes a relationship" do
      family = family_fixture()
      {:ok, parent} = People.create_person(family, %{given_name: "John", surname: "Doe"})
      {:ok, child} = People.create_person(family, %{given_name: "Jane", surname: "Doe"})

      {:ok, rel} =
        Relationships.create_relationship(parent, child, "parent", %{role: "father"})

      assert {:ok, _} = Relationships.delete_relationship(rel)
    end
  end

  describe "update_relationship/2" do
    test "updates metadata" do
      family = family_fixture()
      {:ok, a} = People.create_person(family, %{given_name: "Alice", surname: "A"})
      {:ok, b} = People.create_person(family, %{given_name: "Bob", surname: "B"})
      {:ok, rel} = Relationships.create_relationship(a, b, "married", %{marriage_year: 2020})

      assert {:ok, updated} =
               Relationships.update_relationship(rel, %{
                 metadata: %{__type__: "married", marriage_year: 2021}
               })

      assert updated.metadata.marriage_year == 2021
    end
  end

  describe "update_partner_type/3" do
    test "changes married to divorced carrying marriage metadata" do
      family = family_fixture()
      {:ok, a} = People.create_person(family, %{given_name: "Alice", surname: "A"})
      {:ok, b} = People.create_person(family, %{given_name: "Bob", surname: "B"})

      {:ok, rel} =
        Relationships.create_relationship(a, b, "married", %{
          marriage_year: 2020,
          marriage_location: "Paris"
        })

      assert {:ok, updated} =
               Relationships.update_partner_type(rel, "divorced", %{divorce_year: 2023})

      assert updated.type == "divorced"
      assert updated.metadata.marriage_year == 2020
      assert updated.metadata.marriage_location == "Paris"
      assert updated.metadata.divorce_year == 2023
    end

    test "changes relationship to separated" do
      family = family_fixture()
      {:ok, a} = People.create_person(family, %{given_name: "Alice", surname: "A"})
      {:ok, b} = People.create_person(family, %{given_name: "Bob", surname: "B"})

      {:ok, rel} = Relationships.create_relationship(a, b, "relationship")

      assert {:ok, updated} =
               Relationships.update_partner_type(rel, "separated", %{separated_year: 2023})

      assert updated.type == "separated"
      assert updated.metadata.separated_year == 2023
    end

    test "changes divorced back to married" do
      family = family_fixture()
      {:ok, a} = People.create_person(family, %{given_name: "Alice", surname: "A"})
      {:ok, b} = People.create_person(family, %{given_name: "Bob", surname: "B"})

      {:ok, rel} =
        Relationships.create_relationship(a, b, "divorced", %{
          marriage_year: 2015,
          divorce_year: 2020
        })

      assert {:ok, updated} =
               Relationships.update_partner_type(rel, "married", %{marriage_year: 2022})

      assert updated.type == "married"
      assert updated.metadata.marriage_year == 2022
    end
  end

  describe "one partner-type relationship per pair" do
    test "prevents creating a second partner-type relationship" do
      family = family_fixture()
      {:ok, a} = People.create_person(family, %{given_name: "Alice", surname: "A"})
      {:ok, b} = People.create_person(family, %{given_name: "Bob", surname: "B"})

      {:ok, _} = Relationships.create_relationship(a, b, "married", %{marriage_year: 2020})

      assert {:error, :partner_relationship_exists} =
               Relationships.create_relationship(a, b, "divorced")
    end
  end

  describe "get_parents/1" do
    test "returns parents of a person" do
      family = family_fixture()
      {:ok, father} = People.create_person(family, %{given_name: "John", surname: "D"})
      {:ok, mother} = People.create_person(family, %{given_name: "Jane", surname: "D"})
      {:ok, child} = People.create_person(family, %{given_name: "Kid", surname: "D"})

      {:ok, _} = Relationships.create_relationship(father, child, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mother, child, "parent", %{role: "mother"})

      parents = Relationships.get_parents(child.id)
      assert length(parents) == 2
      parent_ids = Enum.map(parents, fn {person, _rel} -> person.id end)
      assert father.id in parent_ids
      assert mother.id in parent_ids
    end

    test "filters parents by family_id" do
      family1 = family_fixture(%{name: "Family 1"})
      family2 = family_fixture(%{name: "Family 2"})

      {:ok, father} = People.create_person(family1, %{given_name: "Dad", surname: "D"})
      {:ok, mother} = People.create_person(family2, %{given_name: "Mom", surname: "D"})
      {:ok, child} = People.create_person(family1, %{given_name: "Kid", surname: "D"})
      People.add_to_family(child, family2)

      {:ok, _} = Relationships.create_relationship(father, child, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mother, child, "parent", %{role: "mother"})

      # Without family_id — returns both parents (global)
      assert length(Relationships.get_parents(child.id)) == 2

      # With family_id — only returns the parent who is in that family
      family1_parents = Relationships.get_parents(child.id, family_id: family1.id)
      assert length(family1_parents) == 1
      assert {parent, _rel} = hd(family1_parents)
      assert parent.id == father.id

      family2_parents = Relationships.get_parents(child.id, family_id: family2.id)
      assert length(family2_parents) == 1
      assert {parent, _rel} = hd(family2_parents)
      assert parent.id == mother.id
    end
  end

  describe "get_children/1" do
    test "returns children of a person" do
      family = family_fixture()
      {:ok, parent} = People.create_person(family, %{given_name: "John", surname: "D"})
      {:ok, child1} = People.create_person(family, %{given_name: "Kid1", surname: "D"})
      {:ok, child2} = People.create_person(family, %{given_name: "Kid2", surname: "D"})

      {:ok, _} = Relationships.create_relationship(parent, child1, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(parent, child2, "parent", %{role: "father"})

      children = Relationships.get_children(parent.id)
      assert length(children) == 2
      child_ids = Enum.map(children, & &1.id)
      assert child1.id in child_ids
      assert child2.id in child_ids
    end

    test "filters children by family_id" do
      family1 = family_fixture(%{name: "Family 1"})
      family2 = family_fixture(%{name: "Family 2"})

      {:ok, parent} = People.create_person(family1, %{given_name: "Dad", surname: "D"})
      People.add_to_family(parent, family2)
      {:ok, child1} = People.create_person(family1, %{given_name: "Kid1", surname: "D"})
      {:ok, child2} = People.create_person(family2, %{given_name: "Kid2", surname: "D"})

      {:ok, _} = Relationships.create_relationship(parent, child1, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(parent, child2, "parent", %{role: "father"})

      assert length(Relationships.get_children(parent.id)) == 2

      f1_children = Relationships.get_children(parent.id, family_id: family1.id)
      assert length(f1_children) == 1
      assert hd(f1_children).id == child1.id

      f2_children = Relationships.get_children(parent.id, family_id: family2.id)
      assert length(f2_children) == 1
      assert hd(f2_children).id == child2.id
    end
  end

  describe "get_active_partners/1" do
    test "returns current partners from both sides" do
      family = family_fixture()
      {:ok, a} = People.create_person(family, %{given_name: "Alice", surname: "A"})
      {:ok, b} = People.create_person(family, %{given_name: "Bob", surname: "B"})

      {:ok, _} = Relationships.create_relationship(a, b, "married", %{marriage_year: 2020})

      partners_a = Relationships.get_active_partners(a.id)
      assert length(partners_a) == 1
      assert {partner, _rel} = hd(partners_a)
      assert partner.id == b.id

      partners_b = Relationships.get_active_partners(b.id)
      assert length(partners_b) == 1
      assert {partner_b, _rel} = hd(partners_b)
      assert partner_b.id == a.id
    end

    test "filters partners by family_id" do
      family1 = family_fixture(%{name: "Family 1"})
      family2 = family_fixture(%{name: "Family 2"})

      {:ok, person} = People.create_person(family1, %{given_name: "Person", surname: "P"})
      People.add_to_family(person, family2)
      {:ok, partner1} = People.create_person(family1, %{given_name: "Partner1", surname: "P"})
      {:ok, partner2} = People.create_person(family2, %{given_name: "Partner2", surname: "P"})

      {:ok, _} = Relationships.create_relationship(person, partner1, "married")
      {:ok, _} = Relationships.create_relationship(person, partner2, "married")

      assert length(Relationships.get_active_partners(person.id)) == 2

      f1_partners = Relationships.get_active_partners(person.id, family_id: family1.id)
      assert length(f1_partners) == 1
      assert {p, _} = hd(f1_partners)
      assert p.id == partner1.id
    end
  end

  describe "get_former_partners/1" do
    test "returns former partners" do
      family = family_fixture()
      {:ok, a} = People.create_person(family, %{given_name: "Alice", surname: "A"})
      {:ok, b} = People.create_person(family, %{given_name: "Bob", surname: "B"})

      {:ok, _} =
        Relationships.create_relationship(a, b, "divorced", %{
          marriage_year: 2010,
          divorce_year: 2015
        })

      exes = Relationships.get_former_partners(a.id)
      assert length(exes) == 1
      assert {ex, _rel} = hd(exes)
      assert ex.id == b.id
    end

    test "filters former partners by family_id" do
      family1 = family_fixture(%{name: "Family 1"})
      family2 = family_fixture(%{name: "Family 2"})

      {:ok, person} = People.create_person(family1, %{given_name: "Person", surname: "P"})
      People.add_to_family(person, family2)
      {:ok, ex1} = People.create_person(family1, %{given_name: "Ex1", surname: "P"})
      {:ok, ex2} = People.create_person(family2, %{given_name: "Ex2", surname: "P"})

      {:ok, _} =
        Relationships.create_relationship(person, ex1, "divorced", %{
          marriage_year: 2010,
          divorce_year: 2015
        })

      {:ok, _} =
        Relationships.create_relationship(person, ex2, "divorced", %{
          marriage_year: 2012,
          divorce_year: 2016
        })

      assert length(Relationships.get_former_partners(person.id)) == 2

      f1_exes = Relationships.get_former_partners(person.id, family_id: family1.id)
      assert length(f1_exes) == 1
      assert {ex, _} = hd(f1_exes)
      assert ex.id == ex1.id
    end
  end

  describe "get_children_of_pair/2" do
    test "returns children shared by two specific parents" do
      family = family_fixture()
      {:ok, father} = People.create_person(family, %{given_name: "Dad", surname: "D"})
      {:ok, mother} = People.create_person(family, %{given_name: "Mom", surname: "D"})
      {:ok, child1} = People.create_person(family, %{given_name: "Kid1", surname: "D"})
      {:ok, child2} = People.create_person(family, %{given_name: "Kid2", surname: "D"})
      {:ok, solo_child} = People.create_person(family, %{given_name: "Solo", surname: "D"})

      {:ok, _} = Relationships.create_relationship(father, child1, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mother, child1, "parent", %{role: "mother"})
      {:ok, _} = Relationships.create_relationship(father, child2, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mother, child2, "parent", %{role: "mother"})

      {:ok, _} =
        Relationships.create_relationship(father, solo_child, "parent", %{role: "father"})

      shared = Relationships.get_children_of_pair(father.id, mother.id)
      assert length(shared) == 2
      ids = Enum.map(shared, & &1.id)
      assert child1.id in ids
      assert child2.id in ids
      refute solo_child.id in ids
    end

    test "filters children of pair by family_id" do
      family1 = family_fixture(%{name: "Family 1"})
      family2 = family_fixture(%{name: "Family 2"})

      {:ok, father} = People.create_person(family1, %{given_name: "Dad", surname: "D"})
      {:ok, mother} = People.create_person(family1, %{given_name: "Mom", surname: "D"})
      People.add_to_family(father, family2)
      People.add_to_family(mother, family2)
      {:ok, child1} = People.create_person(family1, %{given_name: "Kid1", surname: "D"})
      {:ok, child2} = People.create_person(family2, %{given_name: "Kid2", surname: "D"})

      {:ok, _} = Relationships.create_relationship(father, child1, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mother, child1, "parent", %{role: "mother"})
      {:ok, _} = Relationships.create_relationship(father, child2, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mother, child2, "parent", %{role: "mother"})

      assert length(Relationships.get_children_of_pair(father.id, mother.id)) == 2

      f1 = Relationships.get_children_of_pair(father.id, mother.id, family_id: family1.id)
      assert length(f1) == 1
      assert hd(f1).id == child1.id
    end
  end

  describe "get_solo_children/1" do
    test "returns children with only one parent (this person)" do
      family = family_fixture()
      {:ok, parent} = People.create_person(family, %{given_name: "Dad", surname: "D"})
      {:ok, mother} = People.create_person(family, %{given_name: "Mom", surname: "D"})
      {:ok, paired_child} = People.create_person(family, %{given_name: "Paired", surname: "D"})
      {:ok, solo_child} = People.create_person(family, %{given_name: "Solo", surname: "D"})

      {:ok, _} =
        Relationships.create_relationship(parent, paired_child, "parent", %{role: "father"})

      {:ok, _} =
        Relationships.create_relationship(mother, paired_child, "parent", %{role: "mother"})

      {:ok, _} =
        Relationships.create_relationship(parent, solo_child, "parent", %{role: "father"})

      solo = Relationships.get_solo_children(parent.id)
      assert length(solo) == 1
      assert hd(solo).id == solo_child.id
    end

    test "filters solo children by family_id" do
      family1 = family_fixture(%{name: "Family 1"})
      family2 = family_fixture(%{name: "Family 2"})

      {:ok, parent} = People.create_person(family1, %{given_name: "Dad", surname: "D"})
      People.add_to_family(parent, family2)
      {:ok, solo1} = People.create_person(family1, %{given_name: "Solo1", surname: "D"})
      {:ok, solo2} = People.create_person(family2, %{given_name: "Solo2", surname: "D"})

      {:ok, _} = Relationships.create_relationship(parent, solo1, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(parent, solo2, "parent", %{role: "father"})

      assert length(Relationships.get_solo_children(parent.id)) == 2

      f1 = Relationships.get_solo_children(parent.id, family_id: family1.id)
      assert length(f1) == 1
      assert hd(f1).id == solo1.id
    end
  end

  describe "get_siblings/1" do
    test "returns full siblings sharing both parents" do
      family = family_fixture()
      {:ok, father} = People.create_person(family, %{given_name: "Dad", surname: "D"})
      {:ok, mother} = People.create_person(family, %{given_name: "Mom", surname: "D"})
      {:ok, child1} = People.create_person(family, %{given_name: "Kid1", surname: "D"})
      {:ok, child2} = People.create_person(family, %{given_name: "Kid2", surname: "D"})

      {:ok, _} = Relationships.create_relationship(father, child1, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mother, child1, "parent", %{role: "mother"})
      {:ok, _} = Relationships.create_relationship(father, child2, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mother, child2, "parent", %{role: "mother"})

      siblings = Relationships.get_siblings(child1.id)
      assert length(siblings) == 1
      assert {sibling, parent_a_id, parent_b_id} = hd(siblings)
      assert sibling.id == child2.id
      assert parent_a_id in [father.id, mother.id]
      assert parent_b_id in [father.id, mother.id]
    end

    test "returns half-siblings sharing one parent" do
      family = family_fixture()
      {:ok, father} = People.create_person(family, %{given_name: "Dad", surname: "D"})
      {:ok, mother1} = People.create_person(family, %{given_name: "Mom1", surname: "D"})
      {:ok, mother2} = People.create_person(family, %{given_name: "Mom2", surname: "D"})
      {:ok, child1} = People.create_person(family, %{given_name: "Kid1", surname: "D"})
      {:ok, child2} = People.create_person(family, %{given_name: "Kid2", surname: "D"})

      {:ok, _} = Relationships.create_relationship(father, child1, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mother1, child1, "parent", %{role: "mother"})
      {:ok, _} = Relationships.create_relationship(father, child2, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mother2, child2, "parent", %{role: "mother"})

      siblings = Relationships.get_siblings(child1.id)
      assert length(siblings) == 1
      assert {sibling, shared_parent_id} = hd(siblings)
      assert sibling.id == child2.id
      assert shared_parent_id == father.id
    end

    test "returns empty list when no parents" do
      family = family_fixture()
      {:ok, child} = People.create_person(family, %{given_name: "Lonely", surname: "Kid"})
      assert Relationships.get_siblings(child.id) == []
    end

    test "single parent - all other children are half-siblings" do
      family = family_fixture()
      {:ok, father} = People.create_person(family, %{given_name: "Dad", surname: "D"})
      {:ok, child1} = People.create_person(family, %{given_name: "Kid1", surname: "D"})
      {:ok, child2} = People.create_person(family, %{given_name: "Kid2", surname: "D"})

      {:ok, _} = Relationships.create_relationship(father, child1, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(father, child2, "parent", %{role: "father"})

      siblings = Relationships.get_siblings(child1.id)
      assert length(siblings) == 1
      assert {sibling, shared_parent_id} = hd(siblings)
      assert sibling.id == child2.id
      assert shared_parent_id == father.id
    end
  end

  describe "get_children_with_coparents/1" do
    test "returns {child, coparent} when child has two parents" do
      family = family_fixture()
      {:ok, father} = People.create_person(family, %{given_name: "Dad", surname: "D"})
      {:ok, mother} = People.create_person(family, %{given_name: "Mom", surname: "D"})
      {:ok, child} = People.create_person(family, %{given_name: "Kid", surname: "D"})

      {:ok, _} = Relationships.create_relationship(father, child, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mother, child, "parent", %{role: "mother"})

      results = Relationships.get_children_with_coparents(father.id)
      assert [{returned_child, returned_coparent}] = results
      assert returned_child.id == child.id
      assert returned_coparent.id == mother.id
    end

    test "returns {child, nil} when child has only one parent" do
      family = family_fixture()
      {:ok, parent} = People.create_person(family, %{given_name: "Dad", surname: "D"})
      {:ok, child} = People.create_person(family, %{given_name: "Solo", surname: "D"})

      {:ok, _} = Relationships.create_relationship(parent, child, "parent", %{role: "father"})

      results = Relationships.get_children_with_coparents(parent.id)
      assert [{returned_child, nil}] = results
      assert returned_child.id == child.id
    end

    test "returns multiple children with different co-parents" do
      family = family_fixture()
      {:ok, father} = People.create_person(family, %{given_name: "Dad", surname: "D"})
      {:ok, mother1} = People.create_person(family, %{given_name: "Mom1", surname: "D"})
      {:ok, mother2} = People.create_person(family, %{given_name: "Mom2", surname: "D"})
      {:ok, child1} = People.create_person(family, %{given_name: "Kid1", surname: "D"})
      {:ok, child2} = People.create_person(family, %{given_name: "Kid2", surname: "D"})
      {:ok, solo} = People.create_person(family, %{given_name: "Solo", surname: "D"})

      {:ok, _} = Relationships.create_relationship(father, child1, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mother1, child1, "parent", %{role: "mother"})
      {:ok, _} = Relationships.create_relationship(father, child2, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(mother2, child2, "parent", %{role: "mother"})
      {:ok, _} = Relationships.create_relationship(father, solo, "parent", %{role: "father"})

      results = Relationships.get_children_with_coparents(father.id)
      assert length(results) == 3

      result_map = Map.new(results, fn {child, coparent} -> {child.id, coparent} end)
      assert result_map[child1.id].id == mother1.id
      assert result_map[child2.id].id == mother2.id
      assert result_map[solo.id] == nil
    end

    test "returns empty list when person has no children" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "Lonely", surname: "D"})

      assert Relationships.get_children_with_coparents(person.id) == []
    end
  end

  describe "list_relationships_for_family/1" do
    test "returns relationships where both people are in the family" do
      family = family_fixture()
      {:ok, alice} = People.create_person(family, %{given_name: "Alice", surname: "A"})
      {:ok, bob} = People.create_person(family, %{given_name: "Bob", surname: "B"})
      {:ok, rel} = Relationships.create_relationship(alice, bob, "married")

      results = Relationships.list_relationships_for_family(family.id)
      assert length(results) == 1
      assert hd(results).id == rel.id
    end

    test "excludes relationships where one person is outside the family" do
      family1 = family_fixture(%{name: "Family 1"})
      family2 = family_fixture(%{name: "Family 2"})
      {:ok, alice} = People.create_person(family1, %{given_name: "Alice", surname: "A"})
      {:ok, bob} = People.create_person(family2, %{given_name: "Bob", surname: "B"})
      {:ok, _rel} = Relationships.create_relationship(alice, bob, "married")

      assert Relationships.list_relationships_for_family(family1.id) == []
    end

    test "returns all relationship types" do
      family = family_fixture()
      {:ok, parent} = People.create_person(family, %{given_name: "Parent", surname: "P"})
      {:ok, child} = People.create_person(family, %{given_name: "Child", surname: "C"})
      {:ok, partner} = People.create_person(family, %{given_name: "Partner", surname: "X"})
      {:ok, _} = Relationships.create_relationship(parent, child, "parent", %{role: "father"})
      {:ok, _} = Relationships.create_relationship(parent, partner, "married")

      results = Relationships.list_relationships_for_family(family.id)
      assert length(results) == 2
      types = Enum.map(results, & &1.type) |> Enum.sort()
      assert types == ["married", "parent"]
    end
  end

  describe "create_relationship/4 acquaintance guard" do
    setup do
      org = insert(:organization)
      person = insert(:person, organization: org)
      acquaintance = insert(:acquaintance, organization: org)
      %{person: person, acquaintance: acquaintance}
    end

    test "blocks when person_a is acquaintance", %{person: person, acquaintance: acquaintance} do
      assert {:error, :acquaintance_cannot_have_relationships} =
               Relationships.create_relationship(acquaintance, person, "parent", %{role: "father"})
    end

    test "blocks when person_b is acquaintance", %{person: person, acquaintance: acquaintance} do
      assert {:error, :acquaintance_cannot_have_relationships} =
               Relationships.create_relationship(person, acquaintance, "parent", %{role: "father"})
    end
  end

  defp org_fixture do
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})
    org
  end

  defp family_fixture(attrs \\ %{}) do
    org = org_fixture()

    {:ok, family} =
      Ancestry.Families.create_family(org, Enum.into(attrs, %{name: "Test Family"}))

    family
  end
end
