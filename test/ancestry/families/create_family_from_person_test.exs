defmodule Ancestry.Families.CreateFamilyFromPersonTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Families
  alias Ancestry.People

  describe "create_family_from_person/5" do
    test "person with no relationships creates family with only themselves" do
      {org, family, person} = setup_single_person()

      assert {:ok, new_family} =
               Families.create_family_from_person(org, "New Family", person, family.id, [])

      assert new_family.name == "New Family"
      assert new_family.organization_id == org.id

      members = People.list_people_for_family(new_family.id)
      assert length(members) == 1
      assert hd(members).id == person.id
    end

    test "includes parents, children, and active partners" do
      {org, family, person, parent, child, partner} = setup_full_family()

      {:ok, new_family} =
        Families.create_family_from_person(org, "New", person, family.id, [])

      member_ids =
        People.list_people_for_family(new_family.id) |> Enum.map(& &1.id) |> MapSet.new()

      assert MapSet.member?(member_ids, person.id)
      assert MapSet.member?(member_ids, parent.id)
      assert MapSet.member?(member_ids, child.id)
      assert MapSet.member?(member_ids, partner.id)
      assert MapSet.size(member_ids) == 4
    end

    test "with include_partner_ancestors: false, partner's parents are excluded" do
      {org, family, person, _parent, _child, partner} = setup_full_family()
      partner_parent = person_fixture(family, %{given_name: "Eve", surname: "Jones"})

      {:ok, _} =
        Ancestry.Relationships.create_relationship(partner_parent, partner, "parent", %{
          role: "mother"
        })

      {:ok, new_family} =
        Families.create_family_from_person(org, "New", person, family.id,
          include_partner_ancestors: false
        )

      member_ids =
        People.list_people_for_family(new_family.id) |> Enum.map(& &1.id) |> MapSet.new()

      assert MapSet.member?(member_ids, partner.id)
      refute MapSet.member?(member_ids, partner_parent.id)
    end

    test "with include_partner_ancestors: true, partner's parents are included" do
      {org, family, person, _parent, _child, partner} = setup_full_family()
      partner_parent = person_fixture(family, %{given_name: "Eve", surname: "Jones"})

      {:ok, _} =
        Ancestry.Relationships.create_relationship(partner_parent, partner, "parent", %{
          role: "mother"
        })

      {:ok, new_family} =
        Families.create_family_from_person(org, "New", person, family.id,
          include_partner_ancestors: true
        )

      member_ids =
        People.list_people_for_family(new_family.id) |> Enum.map(& &1.id) |> MapSet.new()

      assert MapSet.member?(member_ids, partner.id)
      assert MapSet.member?(member_ids, partner_parent.id)
    end

    test "people not in source family are excluded even if they have relationships" do
      org = org_fixture()
      family = family_fixture(org)
      other_family = family_fixture(org, %{name: "Other Family"})

      person = person_fixture(family, %{given_name: "Alice", surname: "Smith"})
      outside_parent = person_fixture(other_family, %{given_name: "Bob", surname: "Smith"})

      {:ok, _} =
        Ancestry.Relationships.create_relationship(outside_parent, person, "parent", %{
          role: "father"
        })

      {:ok, new_family} =
        Families.create_family_from_person(org, "New", person, family.id, [])

      member_ids =
        People.list_people_for_family(new_family.id) |> Enum.map(& &1.id) |> MapSet.new()

      assert MapSet.member?(member_ids, person.id)
      refute MapSet.member?(member_ids, outside_parent.id)
      assert MapSet.size(member_ids) == 1
    end

    test "selected person is set as default member of the new family" do
      {org, family, person} = setup_single_person()

      {:ok, new_family} =
        Families.create_family_from_person(org, "New", person, family.id, [])

      default = People.get_default_person(new_family.id)
      assert default.id == person.id
    end

    test "partner's children from other relationships are NOT included" do
      org = org_fixture()
      family = family_fixture(org)

      alice = person_fixture(family, %{given_name: "Alice", surname: "Smith"})
      bob = person_fixture(family, %{given_name: "Bob", surname: "Jones"})
      # Carol is Bob's child from a prior relationship — not Alice's descendant
      carol = person_fixture(family, %{given_name: "Carol", surname: "Jones"})

      {:ok, _} = Ancestry.Relationships.create_relationship(alice, bob, "married")

      {:ok, _} =
        Ancestry.Relationships.create_relationship(bob, carol, "parent", %{role: "father"})

      {:ok, new_family} =
        Families.create_family_from_person(org, "New", alice, family.id, [])

      member_ids =
        People.list_people_for_family(new_family.id) |> Enum.map(& &1.id) |> MapSet.new()

      assert MapSet.member?(member_ids, alice.id)
      assert MapSet.member?(member_ids, bob.id)
      # Carol should NOT be included — she's Bob's child, not Alice's
      refute MapSet.member?(member_ids, carol.id)
      assert MapSet.size(member_ids) == 2
    end

    test "with include_ancestors: false, ascendants are excluded" do
      {org, family, person, parent, child, partner} = setup_full_family()

      {:ok, new_family} =
        Families.create_family_from_person(org, "New", person, family.id,
          include_ancestors: false
        )

      member_ids =
        People.list_people_for_family(new_family.id) |> Enum.map(& &1.id) |> MapSet.new()

      assert MapSet.member?(member_ids, person.id)
      assert MapSet.member?(member_ids, child.id)
      assert MapSet.member?(member_ids, partner.id)
      refute MapSet.member?(member_ids, parent.id)
    end

    test "siblings are NOT included (only ascendants, descendants, partners)" do
      org = org_fixture()
      family = family_fixture(org)

      parent = person_fixture(family, %{given_name: "Parent", surname: "Smith"})
      person = person_fixture(family, %{given_name: "Alice", surname: "Smith"})
      sibling = person_fixture(family, %{given_name: "Sibling", surname: "Smith"})

      {:ok, _} =
        Ancestry.Relationships.create_relationship(parent, person, "parent", %{role: "father"})

      {:ok, _} =
        Ancestry.Relationships.create_relationship(parent, sibling, "parent", %{role: "father"})

      {:ok, new_family} =
        Families.create_family_from_person(org, "New", person, family.id, [])

      member_ids =
        People.list_people_for_family(new_family.id) |> Enum.map(& &1.id) |> MapSet.new()

      # Person and parent should be included (parent is an ascendant)
      assert MapSet.member?(member_ids, person.id)
      assert MapSet.member?(member_ids, parent.id)
      # Sibling should NOT be included — they are not an ascendant, descendant, or partner
      refute MapSet.member?(member_ids, sibling.id)
      assert MapSet.size(member_ids) == 2
    end

    test "descendant's partner is included but not partner's own descendants" do
      org = org_fixture()
      family = family_fixture(org)

      alice = person_fixture(family, %{given_name: "Alice", surname: "Smith"})
      child = person_fixture(family, %{given_name: "Child", surname: "Smith"})
      child_partner = person_fixture(family, %{given_name: "ChildPartner", surname: "Jones"})
      # ChildPartner's child from another relationship (not with Child)
      step_grandchild = person_fixture(family, %{given_name: "StepGrand", surname: "Jones"})
      # Alice's grandchild (child of Child)
      grandchild = person_fixture(family, %{given_name: "Grandchild", surname: "Smith"})

      {:ok, _} =
        Ancestry.Relationships.create_relationship(alice, child, "parent", %{role: "mother"})

      {:ok, _} = Ancestry.Relationships.create_relationship(child, child_partner, "married")

      {:ok, _} =
        Ancestry.Relationships.create_relationship(child_partner, step_grandchild, "parent", %{
          role: "father"
        })

      {:ok, _} =
        Ancestry.Relationships.create_relationship(child, grandchild, "parent", %{
          role: "father"
        })

      {:ok, new_family} =
        Families.create_family_from_person(org, "New", alice, family.id, [])

      member_ids =
        People.list_people_for_family(new_family.id) |> Enum.map(& &1.id) |> MapSet.new()

      assert MapSet.member?(member_ids, alice.id)
      assert MapSet.member?(member_ids, child.id)
      assert MapSet.member?(member_ids, child_partner.id)
      assert MapSet.member?(member_ids, grandchild.id)
      # StepGrand is ChildPartner's child, not Alice's descendant
      refute MapSet.member?(member_ids, step_grandchild.id)
    end

    test "returns error changeset when family name is blank" do
      {org, family, person} = setup_single_person()

      assert {:error, changeset} =
               Families.create_family_from_person(org, "", person, family.id, [])

      assert "can't be blank" in errors_on(changeset).name
    end

    test "person already in multiple families can be added to the new family" do
      org = org_fixture()
      family_a = family_fixture(org, %{name: "Family A"})
      family_b = family_fixture(org, %{name: "Family B"})

      person = person_fixture(family_a, %{given_name: "Alice", surname: "Smith"})
      People.add_to_family(person, family_b)

      assert {:ok, new_family} =
               Families.create_family_from_person(org, "New", person, family_a.id, [])

      members = People.list_people_for_family(new_family.id)
      assert length(members) == 1
      assert hd(members).id == person.id

      person = People.get_person!(person.id)
      assert length(person.families) == 3
    end
  end

  defp org_fixture do
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})
    org
  end

  defp family_fixture(org, attrs \\ %{}) do
    {:ok, family} = Families.create_family(org, Enum.into(attrs, %{name: "Source Family"}))
    family
  end

  defp person_fixture(family, attrs) do
    {:ok, person} =
      People.create_person(
        family,
        Enum.into(attrs, %{given_name: "Test", surname: "Person"})
      )

    person
  end

  defp setup_single_person do
    org = org_fixture()
    family = family_fixture(org)
    person = person_fixture(family, %{given_name: "Alice", surname: "Smith"})
    {org, family, person}
  end

  defp setup_full_family do
    org = org_fixture()
    family = family_fixture(org)
    person = person_fixture(family, %{given_name: "Alice", surname: "Smith"})
    parent = person_fixture(family, %{given_name: "Bob", surname: "Smith"})
    child = person_fixture(family, %{given_name: "Charlie", surname: "Smith"})
    partner = person_fixture(family, %{given_name: "Dave", surname: "Jones"})

    {:ok, _} =
      Ancestry.Relationships.create_relationship(parent, person, "parent", %{role: "father"})

    {:ok, _} =
      Ancestry.Relationships.create_relationship(person, child, "parent", %{role: "mother"})

    {:ok, _} = Ancestry.Relationships.create_relationship(person, partner, "married")

    {org, family, person, parent, child, partner}
  end
end
