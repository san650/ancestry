defmodule Ancestry.FamiliesTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Families
  alias Ancestry.Families.Family

  describe "families" do
    test "list_families/1 returns all families ordered by name" do
      {org, _} = org_fixture()
      f1 = family_fixture(org, %{name: "Beta"})
      f2 = family_fixture(org, %{name: "Alpha"})
      assert Families.list_families(org.id) == [f2, f1]
    end

    test "get_family!/1 returns the family with given id" do
      {org, _} = org_fixture()
      family = family_fixture(org)
      assert Families.get_family!(family.id) == family
    end

    test "create_family/2 with valid data creates a family" do
      {org, _} = org_fixture()
      assert {:ok, %Family{} = family} = Families.create_family(org, %{name: "The Smiths"})
      assert family.name == "The Smiths"
    end

    test "create_family/2 with blank name returns error changeset" do
      {org, _} = org_fixture()
      assert {:error, %Ecto.Changeset{}} = Families.create_family(org, %{name: ""})
    end

    test "update_family/2 updates the family name" do
      {org, _} = org_fixture()
      family = family_fixture(org)
      assert {:ok, %Family{} = updated} = Families.update_family(family, %{name: "New Name"})
      assert updated.name == "New Name"
    end

    test "delete_family/1 deletes the family" do
      {org, _} = org_fixture()
      family = family_fixture(org)
      assert {:ok, %Family{}} = Families.delete_family(family)
      assert_raise Ecto.NoResultsError, fn -> Families.get_family!(family.id) end
    end

    test "change_family/2 returns a family changeset" do
      {org, _} = org_fixture()
      family = family_fixture(org)
      assert %Ecto.Changeset{} = Families.change_family(family)
    end
  end

  defp org_fixture do
    {:ok, org} = Ancestry.Organizations.create_organization(%{name: "Test Org"})
    {org, org}
  end

  defp family_fixture(org, attrs \\ %{}) do
    {:ok, family} =
      Families.create_family(org, Enum.into(attrs, %{name: "Test Family"}))

    family
  end
end
