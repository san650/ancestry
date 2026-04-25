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
end
