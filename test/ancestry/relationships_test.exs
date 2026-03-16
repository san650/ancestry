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

  defp family_fixture(attrs \\ %{}) do
    {:ok, family} =
      attrs
      |> Enum.into(%{name: "Test Family"})
      |> Ancestry.Families.create_family()

    family
  end
end
