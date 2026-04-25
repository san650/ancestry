defmodule Ancestry.People.PersonKindTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.People.Person

  describe "changeset/2 kind field" do
    test "defaults kind to family_member" do
      changeset = Person.changeset(%Person{}, %{given_name: "John", surname: "Doe"})
      assert get_field(changeset, :kind) == "family_member"
    end

    test "accepts acquaintance as kind" do
      changeset =
        Person.changeset(%Person{}, %{given_name: "John", surname: "Doe", kind: "acquaintance"})

      assert changeset.valid?
      assert get_field(changeset, :kind) == "acquaintance"
    end

    test "rejects invalid kind values" do
      changeset =
        Person.changeset(%Person{}, %{given_name: "John", surname: "Doe", kind: "stranger"})

      assert "is invalid" in errors_on(changeset).kind
    end
  end

  describe "acquaintance?/1" do
    test "returns true for acquaintance" do
      assert Person.acquaintance?(%Person{kind: "acquaintance"})
    end

    test "returns false for family_member" do
      refute Person.acquaintance?(%Person{kind: "family_member"})
    end
  end

  describe "changeset/2 name_search computation" do
    test "computes name_search from given_name and surname" do
      changeset = Person.changeset(%Person{}, %{given_name: "Martín", surname: "Vazquez"})
      assert get_field(changeset, :name_search) =~ "martin"
      assert get_field(changeset, :name_search) =~ "vazquez"
    end

    test "includes nickname in name_search" do
      changeset =
        Person.changeset(%Person{}, %{
          given_name: "Martín",
          surname: "Vazquez",
          nickname: "Tincho"
        })

      assert get_field(changeset, :name_search) =~ "tincho"
    end

    test "includes alternate_names in name_search" do
      changeset =
        Person.changeset(%Person{}, %{
          given_name: "Martín",
          surname: "Vazquez",
          alternate_names: ["Martín José"]
        })

      assert get_field(changeset, :name_search) =~ "martin jose"
    end

    test "includes birth names in name_search" do
      changeset =
        Person.changeset(%Person{}, %{
          given_name: "María",
          surname: "López",
          given_name_at_birth: "María",
          surname_at_birth: "García"
        })

      assert get_field(changeset, :name_search) =~ "garcia"
    end

    test "strips diacritics in name_search" do
      changeset = Person.changeset(%Person{}, %{given_name: "Ñoño", surname: "Müller"})
      assert get_field(changeset, :name_search) =~ "nono"
      assert get_field(changeset, :name_search) =~ "muller"
    end

    test "handles all nil name fields" do
      changeset = Person.changeset(%Person{}, %{})
      name_search = get_field(changeset, :name_search)
      assert name_search == ""
    end

    test "updates name_search when name fields change" do
      person = %Person{given_name: "Old", surname: "Name", name_search: "old name"}
      changeset = Person.changeset(person, %{given_name: "New"})
      assert get_field(changeset, :name_search) =~ "new"
    end
  end
end
