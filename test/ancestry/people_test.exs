defmodule Ancestry.PeopleTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.People.Person

  describe "person changeset" do
    test "valid changeset with minimal fields" do
      changeset = Person.changeset(%Person{}, %{given_name: "John", surname: "Doe"})
      assert changeset.valid?
    end

    test "defaults living to yes" do
      changeset = Person.changeset(%Person{}, %{given_name: "John", surname: "Doe"})
      assert Ecto.Changeset.get_field(changeset, :living) == "yes"
    end

    test "validates living is one of yes, no, unknown" do
      changeset =
        Person.changeset(%Person{}, %{given_name: "John", surname: "Doe", living: "maybe"})

      assert "is invalid" in errors_on(changeset).living
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

    test "display_name/1 handles nil given_name" do
      person = %Person{given_name: nil, surname: "Doe"}
      assert Person.display_name(person) == "Doe"
    end

    test "display_name/1 handles nil surname" do
      person = %Person{given_name: "John", surname: nil}
      assert Person.display_name(person) == "John"
    end
  end
end
