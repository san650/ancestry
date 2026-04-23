defmodule Ancestry.PeopleTest do
  use Ancestry.DataCase, async: true

  import Ancestry.Factory

  alias Ancestry.People
  alias Ancestry.People.Person
  alias Ancestry.Relationships

  describe "person changeset" do
    test "valid changeset with minimal fields" do
      changeset = Person.changeset(%Person{}, %{given_name: "John", surname: "Doe"})
      assert changeset.valid?
    end

    test "defaults deceased to false" do
      changeset = Person.changeset(%Person{}, %{given_name: "John", surname: "Doe"})
      assert Ecto.Changeset.get_field(changeset, :deceased) == false
    end

    test "validates gender is one of female, male, other" do
      changeset =
        Person.changeset(%Person{}, %{given_name: "John", surname: "Doe", gender: "invalid"})

      assert "is invalid" in errors_on(changeset).gender
    end

    test "validates birth_month in 1..12" do
      changeset = Person.changeset(%Person{}, %{given_name: "J", surname: "D", birth_month: 13})
      assert "must be less than or equal to 12" in errors_on(changeset).birth_month
    end

    test "validates birth_day in 1..31" do
      changeset = Person.changeset(%Person{}, %{given_name: "J", surname: "D", birth_day: 0})
      assert "must be greater than or equal to 1" in errors_on(changeset).birth_day
    end

    test "display_name/1 combines given_name and surname" do
      person = %Person{given_name: "John", surname: "Doe"}
      assert Person.display_name(person) == "John Doe"
    end

    test "accepts external_id" do
      changeset =
        Person.changeset(%Person{}, %{given_name: "John", external_id: "family_echo_ABC"})

      assert Ecto.Changeset.get_field(changeset, :external_id) == "family_echo_ABC"
    end

    test "display_name/1 handles nil given_name" do
      person = %Person{given_name: nil, surname: "Doe"}
      assert Person.display_name(person) == "Doe"
    end

    test "display_name/1 handles nil surname" do
      person = %Person{given_name: "John", surname: nil}
      assert Person.display_name(person) == "John"
    end
  end

  describe "create_person/2" do
    test "creates a person and adds to family" do
      family = family_fixture()

      assert {:ok, %Person{} = person} =
               People.create_person(family, %{given_name: "Jane", surname: "Doe"})

      assert person.given_name == "Jane"
      assert person.surname == "Doe"

      people = People.list_people_for_family(family.id)
      assert length(people) == 1
      assert hd(people).id == person.id
    end

    test "creates a deceased person" do
      family = family_fixture()

      assert {:ok, %Person{} = person} =
               People.create_person(family, %{given_name: "J", surname: "D", deceased: true})

      assert person.deceased == true
    end
  end

  describe "list_people_for_family/1" do
    test "returns only people in the given family" do
      {org, _} = org_fixture()
      family1 = family_fixture(org, %{name: "Family One"})
      family2 = family_fixture(org, %{name: "Family Two"})
      {:ok, person1} = People.create_person(family1, %{given_name: "Alice", surname: "A"})
      {:ok, _person2} = People.create_person(family2, %{given_name: "Bob", surname: "B"})

      people = People.list_people_for_family(family1.id)
      assert length(people) == 1
      assert hd(people).id == person1.id
    end
  end

  describe "get_person!/1" do
    test "returns the person" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "Jane", surname: "Doe"})
      fetched = People.get_person!(person.id)
      assert fetched.id == person.id
    end
  end

  describe "update_person/2" do
    test "updates person fields" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "Jane", surname: "Doe"})
      assert {:ok, updated} = People.update_person(person, %{given_name: "Janet"})
      assert updated.given_name == "Janet"
    end
  end

  describe "delete_person/1" do
    test "deletes the person" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "Jane", surname: "Doe"})
      assert {:ok, _} = People.delete_person(person)
      assert_raise Ecto.NoResultsError, fn -> People.get_person!(person.id) end
    end
  end

  describe "add_to_family/2 and remove_from_family/2" do
    test "adds an existing person to another family" do
      {org, _} = org_fixture()
      family1 = family_fixture(org, %{name: "Family One"})
      family2 = family_fixture(org, %{name: "Family Two"})
      {:ok, person} = People.create_person(family1, %{given_name: "Jane", surname: "Doe"})

      assert {:ok, _} = People.add_to_family(person, family2)
      assert length(People.list_people_for_family(family2.id)) == 1
    end

    test "add_to_family returns error for duplicate membership" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "Jane", surname: "Doe"})
      assert {:error, _} = People.add_to_family(person, family)
    end

    test "removes a person from a family" do
      family = family_fixture()
      {:ok, person} = People.create_person(family, %{given_name: "Jane", surname: "Doe"})
      assert {:ok, _} = People.remove_from_family(person, family)
      assert People.list_people_for_family(family.id) == []
    end
  end

  describe "search_people/3" do
    test "searches by given_name, surname, nickname" do
      {org, _} = org_fixture()
      family = family_fixture(org)

      {:ok, _} =
        People.create_person(family, %{
          given_name: "Alice",
          surname: "Wonderland",
          nickname: "Ali"
        })

      {:ok, _} = People.create_person(family, %{given_name: "Bob", surname: "Builder"})

      assert length(People.search_people("alice", family.id, org.id)) == 0
      assert length(People.search_people("bob", family.id, org.id)) == 0
    end

    test "searches by alternate_names" do
      {org, _} = org_fixture()
      family1 = family_fixture(org, %{name: "Family One"})
      family2 = family_fixture(org, %{name: "Family Two"})

      {:ok, _} =
        People.create_person(family1, %{
          given_name: "Robert",
          surname: "Smith",
          alternate_names: ["Bobby", "Rob"]
        })

      results = People.search_people("Bobby", family2.id, org.id)
      assert length(results) == 1
      assert hd(results).given_name == "Robert"

      results = People.search_people("Rob", family2.id, org.id)
      assert length(results) == 1
    end

    test "excludes people already in the family" do
      {org, _} = org_fixture()
      family1 = family_fixture(org, %{name: "Family One"})
      family2 = family_fixture(org, %{name: "Family Two"})
      {:ok, _} = People.create_person(family1, %{given_name: "Alice", surname: "A"})
      {:ok, _} = People.create_person(family2, %{given_name: "Bob", surname: "B"})

      results = People.search_people("Bob", family1.id, org.id)
      assert length(results) == 1
      assert hd(results).given_name == "Bob"

      results = People.search_people("Bob", family2.id, org.id)
      assert length(results) == 0
    end

    test "finds people with diacritics using unaccented search" do
      {org, _} = org_fixture()
      family = family_fixture(org)
      other_family = family_fixture(org, %{name: "Other Family"})

      {:ok, _} = People.create_person(other_family, %{given_name: "María", surname: "González"})

      results = People.search_people("maria", family.id, org.id)
      assert length(results) == 1
      assert hd(results).given_name == "María"

      results = People.search_people("gonzalez", family.id, org.id)
      assert length(results) == 1
      assert hd(results).surname == "González"
    end

    test "finds people without diacritics using accented search" do
      {org, _} = org_fixture()
      family = family_fixture(org)
      other_family = family_fixture(org, %{name: "Other Family"})

      {:ok, _} = People.create_person(other_family, %{given_name: "Maria", surname: "Gonzalez"})

      results = People.search_people("María", family.id, org.id)
      assert length(results) == 1

      results = People.search_people("González", family.id, org.id)
      assert length(results) == 1
    end
  end

  describe "search_all_people/2 diacritics" do
    test "finds people with diacritics using unaccented search" do
      {org, _} = org_fixture()
      family = family_fixture(org)
      {:ok, _} = People.create_person(family, %{given_name: "José", surname: "García"})

      results = People.search_all_people("jose", org.id)
      assert length(results) == 1
      assert hd(results).given_name == "José"
    end
  end

  describe "search_all_people/3 diacritics" do
    test "finds people with diacritics, excluding a given person" do
      {org, _} = org_fixture()
      family = family_fixture(org)
      {:ok, jose} = People.create_person(family, %{given_name: "José", surname: "García"})
      {:ok, _maria} = People.create_person(family, %{given_name: "María", surname: "García"})

      results = People.search_all_people("garcia", jose.id, org.id)
      assert length(results) == 1
      refute hd(results).id == jose.id
    end
  end

  describe "search_family_members/3" do
    test "searches people within a family by name, excluding a specific person" do
      family = family_fixture()
      {:ok, alice} = People.create_person(family, %{given_name: "Alice", surname: "Wonderland"})
      {:ok, bob} = People.create_person(family, %{given_name: "Bob", surname: "Builder"})

      # Alice should not appear when excluding herself
      results = People.search_family_members("ali", family.id, alice.id)
      assert results == []

      # Bob should appear when excluding Alice
      results = People.search_family_members("bob", family.id, alice.id)
      assert length(results) == 1
      assert hd(results).id == bob.id
    end

    test "does not return people from other families" do
      {org, _} = org_fixture()
      family1 = family_fixture(org, %{name: "Family One"})
      family2 = family_fixture(org, %{name: "Family Two"})
      {:ok, alice} = People.create_person(family1, %{given_name: "Alice", surname: "A"})
      {:ok, _bob} = People.create_person(family2, %{given_name: "Bob", surname: "B"})

      results = People.search_family_members("bob", family1.id, alice.id)
      assert results == []
    end

    test "finds family members with diacritics using unaccented search" do
      family = family_fixture()
      {:ok, maria} = People.create_person(family, %{given_name: "María", surname: "López"})
      {:ok, jose} = People.create_person(family, %{given_name: "José", surname: "López"})

      results = People.search_family_members("maria", family.id, jose.id)
      assert length(results) == 1
      assert hd(results).id == maria.id
    end
  end

  describe "change_person/2" do
    test "returns a changeset" do
      assert %Ecto.Changeset{} = People.change_person(%Person{})
    end
  end

  describe "default member" do
    setup do
      org = insert(:organization)
      family = insert(:family, organization: org)
      person_a = insert(:person, given_name: "Alice", surname: "Smith", organization: org)
      person_b = insert(:person, given_name: "Bob", surname: "Smith", organization: org)
      People.add_to_family(person_a, family)
      People.add_to_family(person_b, family)
      %{family: family, person_a: person_a, person_b: person_b}
    end

    test "get_default_person/1 returns nil when no default is set", %{family: family} do
      assert People.get_default_person(family.id) == nil
    end

    test "set_default_member/2 sets the default person", %{family: family, person_a: person_a} do
      assert {:ok, _} = People.set_default_member(family.id, person_a.id)
      assert People.get_default_person(family.id).id == person_a.id
    end

    test "set_default_member/2 replaces existing default", %{
      family: family,
      person_a: person_a,
      person_b: person_b
    } do
      {:ok, _} = People.set_default_member(family.id, person_a.id)
      {:ok, _} = People.set_default_member(family.id, person_b.id)
      assert People.get_default_person(family.id).id == person_b.id
    end

    test "clear_default_member/1 removes the default", %{family: family, person_a: person_a} do
      {:ok, _} = People.set_default_member(family.id, person_a.id)
      assert :ok = People.clear_default_member(family.id)
      assert People.get_default_person(family.id) == nil
    end

    test "removing a member from family clears default automatically", %{
      family: family,
      person_a: person_a
    } do
      {:ok, _} = People.set_default_member(family.id, person_a.id)
      {:ok, _} = People.remove_from_family(person_a, family)
      assert People.get_default_person(family.id) == nil
    end
  end

  describe "list_people_for_family_with_relationship_counts/1" do
    test "returns people with their relationship count within the family" do
      org = insert(:organization)
      family = insert(:family, organization: org)
      alice = insert(:person, given_name: "Alice", surname: "Smith", organization: org)
      bob = insert(:person, given_name: "Bob", surname: "Smith", organization: org)
      charlie = insert(:person, given_name: "Charlie", surname: "Smith", organization: org)

      for p <- [alice, bob, charlie], do: Ancestry.People.add_to_family(p, family)

      {:ok, _} =
        Ancestry.Relationships.create_relationship(alice, bob, "parent", %{role: "mother"})

      {:ok, _} = Ancestry.Relationships.create_relationship(alice, charlie, "relationship")

      results = Ancestry.People.list_people_for_family_with_relationship_counts(family.id)

      assert length(results) == 3

      alice_result = Enum.find(results, fn {p, _} -> p.id == alice.id end)
      bob_result = Enum.find(results, fn {p, _} -> p.id == bob.id end)
      charlie_result = Enum.find(results, fn {p, _} -> p.id == charlie.id end)

      assert {_, 2} = alice_result
      assert {_, 1} = bob_result
      assert {_, 1} = charlie_result
    end

    test "returns 0 count for people with no relationships in the family" do
      org = insert(:organization)
      family = insert(:family, organization: org)
      alice = insert(:person, given_name: "Alice", surname: "Loner", organization: org)
      Ancestry.People.add_to_family(alice, family)

      [{person, count}] =
        Ancestry.People.list_people_for_family_with_relationship_counts(family.id)

      assert person.id == alice.id
      assert count == 0
    end

    test "does not count relationships where the other person is outside the family" do
      org = insert(:organization)
      family = insert(:family, organization: org)
      alice = insert(:person, given_name: "Alice", surname: "Smith", organization: org)
      outsider = insert(:person, given_name: "Outsider", surname: "Jones", organization: org)

      Ancestry.People.add_to_family(alice, family)

      {:ok, _} =
        Ancestry.Relationships.create_relationship(alice, outsider, "parent", %{role: "mother"})

      [{person, count}] =
        Ancestry.People.list_people_for_family_with_relationship_counts(family.id)

      assert person.id == alice.id
      assert count == 0
    end

    test "sorts by surname then given name" do
      org = insert(:organization)
      family = insert(:family, organization: org)
      zara = insert(:person, given_name: "Zara", surname: "Adams", organization: org)
      bob = insert(:person, given_name: "Bob", surname: "Adams", organization: org)
      alice = insert(:person, given_name: "Alice", surname: "Brown", organization: org)

      for p <- [zara, bob, alice], do: Ancestry.People.add_to_family(p, family)

      results = Ancestry.People.list_people_for_family_with_relationship_counts(family.id)
      names = Enum.map(results, fn {p, _} -> {p.surname, p.given_name} end)

      assert names == [{"Adams", "Bob"}, {"Adams", "Zara"}, {"Brown", "Alice"}]
    end
  end

  describe "list_people_for_family_with_relationship_counts/2" do
    test "filters by given_name, surname, and nickname with diacritics support" do
      org = insert(:organization)
      family = insert(:family, organization: org)

      jose =
        insert(:person,
          given_name: "Jos\u00e9",
          surname: "Garc\u00eda",
          nickname: "Pepe",
          organization: org
        )

      maria = insert(:person, given_name: "Mar\u00eda", surname: "L\u00f3pez", organization: org)

      for p <- [jose, maria], do: Ancestry.People.add_to_family(p, family)

      # Search by given name (diacritics insensitive)
      results = Ancestry.People.list_people_for_family_with_relationship_counts(family.id, "jose")
      assert length(results) == 1
      assert {p, _} = hd(results)
      assert p.id == jose.id

      # Search by surname
      results =
        Ancestry.People.list_people_for_family_with_relationship_counts(family.id, "Lopez")

      assert length(results) == 1
      assert {p, _} = hd(results)
      assert p.id == maria.id

      # Search by nickname
      results = Ancestry.People.list_people_for_family_with_relationship_counts(family.id, "Pepe")
      assert length(results) == 1
      assert {p, _} = hd(results)
      assert p.id == jose.id

      # Empty search returns all
      results = Ancestry.People.list_people_for_family_with_relationship_counts(family.id, "")
      assert length(results) == 2
    end
  end

  describe "list_people_for_org/1,2,3" do
    setup do
      org = insert(:organization, name: "Test Org")
      family = insert(:family, name: "Fam A", organization: org)

      alice = insert(:person, given_name: "Alice", surname: "Smith", organization: org)
      bob = insert(:person, given_name: "Bob", surname: "Jones", organization: org)
      orphan = insert(:person, given_name: "Orphan", surname: "Nobody", organization: org)

      # Different org — should never appear
      other_org = insert(:organization, name: "Other")

      _outsider =
        insert(:person, given_name: "Outside", surname: "Person", organization: other_org)

      People.add_to_family(alice, family)
      People.add_to_family(bob, family)
      # orphan has no family

      Relationships.create_relationship(alice, bob, "parent", %{role: "mother"})

      %{org: org, family: family, alice: alice, bob: bob, orphan: orphan}
    end

    test "returns all people in the org with relationship counts", %{
      org: org,
      alice: alice,
      bob: bob,
      orphan: orphan
    } do
      results = People.list_people_for_org(org.id)
      people_map = Map.new(results, fn {p, count} -> {p.id, count} end)

      assert map_size(people_map) == 3
      assert people_map[alice.id] == 1
      assert people_map[bob.id] == 1
      assert people_map[orphan.id] == 0
    end

    test "filters by search term with diacritics", %{org: org} do
      results = People.list_people_for_org(org.id, "alice")
      assert length(results) == 1
      assert elem(hd(results), 0).given_name == "Alice"
    end

    test "returns empty for no match", %{org: org} do
      assert People.list_people_for_org(org.id, "zzzzz") == []
    end

    test "no_family_only filters to people without families", %{org: org, orphan: orphan} do
      results = People.list_people_for_org(org.id, no_family_only: true)
      assert length(results) == 1
      assert elem(hd(results), 0).id == orphan.id
    end

    test "no_family_only with search", %{org: org} do
      results = People.list_people_for_org(org.id, "Orphan", no_family_only: true)
      assert length(results) == 1

      results = People.list_people_for_org(org.id, "Alice", no_family_only: true)
      assert results == []
    end

    test "does not include people from other orgs", %{org: org} do
      results = People.list_people_for_org(org.id)
      given_names = Enum.map(results, fn {p, _} -> p.given_name end)
      refute "Outside" in given_names
    end
  end

  describe "delete_people/1" do
    test "deletes multiple people and cleans up files" do
      org = insert(:organization)
      p1 = insert(:person, given_name: "Del1", organization: org)
      p2 = insert(:person, given_name: "Del2", organization: org)
      p3 = insert(:person, given_name: "Keep", organization: org)

      assert {:ok, _} = People.delete_people([p1.id, p2.id])

      assert_raise Ecto.NoResultsError, fn -> People.get_person!(p1.id) end
      assert_raise Ecto.NoResultsError, fn -> People.get_person!(p2.id) end
      assert People.get_person!(p3.id)
    end

    test "returns ok for empty list" do
      assert {:ok, _} = People.delete_people([])
    end
  end

  describe "external_id uniqueness" do
    test "rejects duplicate external_id within the same organization" do
      org = insert(:organization)
      family = insert(:family, organization: org)

      assert {:ok, _person} =
               People.create_person(family, %{
                 given_name: "Alice",
                 surname: "Smith",
                 external_id: "ext_1"
               })

      assert {:error, changeset} =
               People.create_person(family, %{
                 given_name: "Bob",
                 surname: "Smith",
                 external_id: "ext_1"
               })

      assert "has already been taken" in errors_on(changeset).external_id
    end

    test "allows the same external_id in different organizations" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      family_a = insert(:family, organization: org_a)
      family_b = insert(:family, organization: org_b)

      assert {:ok, person_a} =
               People.create_person(family_a, %{
                 given_name: "Alice",
                 surname: "Smith",
                 external_id: "ext_1"
               })

      assert {:ok, person_b} =
               People.create_person(family_b, %{
                 given_name: "Alice",
                 surname: "Smith",
                 external_id: "ext_1"
               })

      assert person_a.id != person_b.id
      assert person_a.organization_id == org_a.id
      assert person_b.organization_id == org_b.id
    end
  end

  describe "list_birthdays_for_family/1" do
    setup do
      org = insert(:organization)
      family = insert(:family, organization: org)
      %{org: org, family: family}
    end

    test "returns people ordered by birth_month then birth_day", %{org: org, family: family} do
      march_10 =
        insert(:person,
          given_name: "March",
          surname: "Ten",
          birth_month: 3,
          birth_day: 10,
          organization: org
        )

      jan_5 =
        insert(:person,
          given_name: "Jan",
          surname: "Five",
          birth_month: 1,
          birth_day: 5,
          organization: org
        )

      march_1 =
        insert(:person,
          given_name: "March",
          surname: "One",
          birth_month: 3,
          birth_day: 1,
          organization: org
        )

      for p <- [march_10, jan_5, march_1], do: People.add_to_family(p, family)

      results = People.list_birthdays_for_family(family.id)
      ids = Enum.map(results, & &1.id)

      assert ids == [jan_5.id, march_1.id, march_10.id]
    end

    test "excludes people with nil birth_month", %{org: org, family: family} do
      with_birthday =
        insert(:person,
          given_name: "Has",
          surname: "Birthday",
          birth_month: 6,
          birth_day: 15,
          organization: org
        )

      no_month =
        insert(:person,
          given_name: "No",
          surname: "Month",
          birth_month: nil,
          birth_day: 15,
          organization: org
        )

      for p <- [with_birthday, no_month], do: People.add_to_family(p, family)

      results = People.list_birthdays_for_family(family.id)
      ids = Enum.map(results, & &1.id)

      assert with_birthday.id in ids
      refute no_month.id in ids
    end

    test "excludes people with nil birth_day", %{org: org, family: family} do
      with_birthday =
        insert(:person,
          given_name: "Has",
          surname: "Birthday",
          birth_month: 6,
          birth_day: 15,
          organization: org
        )

      no_day =
        insert(:person,
          given_name: "No",
          surname: "Day",
          birth_month: 6,
          birth_day: nil,
          organization: org
        )

      for p <- [with_birthday, no_day], do: People.add_to_family(p, family)

      results = People.list_birthdays_for_family(family.id)
      ids = Enum.map(results, & &1.id)

      assert with_birthday.id in ids
      refute no_day.id in ids
    end

    test "excludes people not in the family", %{org: org, family: family} do
      other_family = insert(:family, organization: org)

      in_family =
        insert(:person,
          given_name: "In",
          surname: "Family",
          birth_month: 4,
          birth_day: 10,
          organization: org
        )

      not_in_family =
        insert(:person,
          given_name: "Not",
          surname: "Family",
          birth_month: 5,
          birth_day: 20,
          organization: org
        )

      People.add_to_family(in_family, family)
      People.add_to_family(not_in_family, other_family)

      results = People.list_birthdays_for_family(family.id)
      ids = Enum.map(results, & &1.id)

      assert in_family.id in ids
      refute not_in_family.id in ids
    end

    test "filters out invalid date combinations like Feb 30", %{org: org, family: family} do
      valid =
        insert(:person,
          given_name: "Valid",
          surname: "Feb",
          birth_month: 2,
          birth_day: 28,
          organization: org
        )

      invalid =
        insert(:person,
          given_name: "Invalid",
          surname: "Feb30",
          birth_month: 2,
          birth_day: 30,
          organization: org
        )

      for p <- [valid, invalid], do: People.add_to_family(p, family)

      results = People.list_birthdays_for_family(family.id)
      ids = Enum.map(results, & &1.id)

      assert valid.id in ids
      refute invalid.id in ids
    end

    test "includes Feb 29 (leap day) birthdays", %{org: org, family: family} do
      leap_day =
        insert(:person,
          given_name: "Leap",
          surname: "Day",
          birth_month: 2,
          birth_day: 29,
          organization: org
        )

      People.add_to_family(leap_day, family)

      results = People.list_birthdays_for_family(family.id)
      ids = Enum.map(results, & &1.id)

      assert leap_day.id in ids
    end
  end

  defp org_fixture do
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})
    {org, org}
  end

  defp family_fixture(org \\ nil, attrs \\ %{}) do
    org =
      case org do
        nil ->
          {o, _} = org_fixture()
          o

        o ->
          o
      end

    {:ok, family} =
      Ancestry.Families.create_family(org, Enum.into(attrs, %{name: "Test Family"}))

    family
  end
end
