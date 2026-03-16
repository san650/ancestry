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
          type: "partner",
          metadata: %{__type__: "partner", marriage_year: 1920}
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
          type: "partner"
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
               Relationships.create_relationship(person_b, person_a, "partner", %{
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
      {:ok, rel} = Relationships.create_relationship(a, b, "partner", %{marriage_year: 2020})

      assert {:ok, updated} =
               Relationships.update_relationship(rel, %{
                 metadata: %{__type__: "partner", marriage_year: 2021}
               })

      assert updated.metadata.marriage_year == 2021
    end
  end

  describe "convert_to_ex_partner/2" do
    test "converts partner to ex_partner carrying marriage metadata" do
      family = family_fixture()
      {:ok, a} = People.create_person(family, %{given_name: "Alice", surname: "A"})
      {:ok, b} = People.create_person(family, %{given_name: "Bob", surname: "B"})

      {:ok, rel} =
        Relationships.create_relationship(a, b, "partner", %{
          marriage_year: 2020,
          marriage_location: "Paris"
        })

      assert {:ok, ex_rel} =
               Relationships.convert_to_ex_partner(rel, %{divorce_year: 2023})

      assert ex_rel.type == "ex_partner"
      assert ex_rel.metadata.marriage_year == 2020
      assert ex_rel.metadata.marriage_location == "Paris"
      assert ex_rel.metadata.divorce_year == 2023
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
  end

  describe "get_partners/1" do
    test "returns current partners from both sides" do
      family = family_fixture()
      {:ok, a} = People.create_person(family, %{given_name: "Alice", surname: "A"})
      {:ok, b} = People.create_person(family, %{given_name: "Bob", surname: "B"})

      {:ok, _} = Relationships.create_relationship(a, b, "partner", %{marriage_year: 2020})

      partners_a = Relationships.get_partners(a.id)
      assert length(partners_a) == 1
      assert {partner, _rel} = hd(partners_a)
      assert partner.id == b.id

      partners_b = Relationships.get_partners(b.id)
      assert length(partners_b) == 1
      assert {partner_b, _rel} = hd(partners_b)
      assert partner_b.id == a.id
    end
  end

  describe "get_ex_partners/1" do
    test "returns ex-partners" do
      family = family_fixture()
      {:ok, a} = People.create_person(family, %{given_name: "Alice", surname: "A"})
      {:ok, b} = People.create_person(family, %{given_name: "Bob", surname: "B"})

      {:ok, _} =
        Relationships.create_relationship(a, b, "ex_partner", %{
          marriage_year: 2010,
          divorce_year: 2015
        })

      exes = Relationships.get_ex_partners(a.id)
      assert length(exes) == 1
      assert {ex, _rel} = hd(exes)
      assert ex.id == b.id
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

  defp family_fixture(attrs \\ %{}) do
    {:ok, family} =
      attrs
      |> Enum.into(%{name: "Test Family"})
      |> Ancestry.Families.create_family()

    family
  end
end
