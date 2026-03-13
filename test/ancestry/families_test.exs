defmodule Ancestry.FamiliesTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Families
  alias Ancestry.Families.Family

  describe "families" do
    test "list_families/0 returns all families ordered by name" do
      f1 = family_fixture(%{name: "Beta"})
      f2 = family_fixture(%{name: "Alpha"})
      assert Families.list_families() == [f2, f1]
    end

    test "get_family!/1 returns the family with given id" do
      family = family_fixture()
      assert Families.get_family!(family.id) == family
    end

    test "create_family/1 with valid data creates a family" do
      assert {:ok, %Family{} = family} = Families.create_family(%{name: "The Smiths"})
      assert family.name == "The Smiths"
    end

    test "create_family/1 with blank name returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Families.create_family(%{name: ""})
    end

    test "update_family/2 updates the family name" do
      family = family_fixture()
      assert {:ok, %Family{} = updated} = Families.update_family(family, %{name: "New Name"})
      assert updated.name == "New Name"
    end

    test "delete_family/1 deletes the family" do
      family = family_fixture()
      assert {:ok, %Family{}} = Families.delete_family(family)
      assert_raise Ecto.NoResultsError, fn -> Families.get_family!(family.id) end
    end

    test "change_family/2 returns a family changeset" do
      family = family_fixture()
      assert %Ecto.Changeset{} = Families.change_family(family)
    end
  end

  defp family_fixture(attrs \\ %{}) do
    {:ok, family} =
      attrs
      |> Enum.into(%{name: "Test Family"})
      |> Families.create_family()

    family
  end
end
