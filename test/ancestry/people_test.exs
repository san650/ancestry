defmodule Ancestry.PeopleTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.People
  alias Ancestry.People.Person

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
      family1 = family_fixture(%{name: "Family One"})
      family2 = family_fixture(%{name: "Family Two"})
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
      family1 = family_fixture(%{name: "Family One"})
      family2 = family_fixture(%{name: "Family Two"})
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

  describe "search_people/2" do
    test "searches by given_name, surname, nickname" do
      family = family_fixture()

      {:ok, _} =
        People.create_person(family, %{
          given_name: "Alice",
          surname: "Wonderland",
          nickname: "Ali"
        })

      {:ok, _} = People.create_person(family, %{given_name: "Bob", surname: "Builder"})

      assert length(People.search_people("alice", family.id)) == 0
      assert length(People.search_people("bob", family.id)) == 0
    end

    test "searches by alternate_names" do
      family1 = family_fixture(%{name: "Family One"})
      family2 = family_fixture(%{name: "Family Two"})

      {:ok, _} =
        People.create_person(family1, %{
          given_name: "Robert",
          surname: "Smith",
          alternate_names: ["Bobby", "Rob"]
        })

      results = People.search_people("Bobby", family2.id)
      assert length(results) == 1
      assert hd(results).given_name == "Robert"

      results = People.search_people("Rob", family2.id)
      assert length(results) == 1
    end

    test "excludes people already in the family" do
      family1 = family_fixture(%{name: "Family One"})
      family2 = family_fixture(%{name: "Family Two"})
      {:ok, _} = People.create_person(family1, %{given_name: "Alice", surname: "A"})
      {:ok, _} = People.create_person(family2, %{given_name: "Bob", surname: "B"})

      results = People.search_people("Bob", family1.id)
      assert length(results) == 1
      assert hd(results).given_name == "Bob"

      results = People.search_people("Bob", family2.id)
      assert length(results) == 0
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
      family1 = family_fixture(%{name: "Family One"})
      family2 = family_fixture(%{name: "Family Two"})
      {:ok, alice} = People.create_person(family1, %{given_name: "Alice", surname: "A"})
      {:ok, _bob} = People.create_person(family2, %{given_name: "Bob", surname: "B"})

      results = People.search_family_members("bob", family1.id, alice.id)
      assert results == []
    end
  end

  describe "change_person/2" do
    test "returns a changeset" do
      assert %Ecto.Changeset{} = People.change_person(%Person{})
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
