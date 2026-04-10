defmodule Ancestry.MemoriesTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Memories
  alias Ancestry.Memories.Vault

  describe "vaults" do
    setup do
      org = insert(:organization)
      family = insert(:family, organization: org)
      %{org: org, family: family}
    end

    test "list_vaults/1 returns vaults for a family ordered by inserted_at desc", %{
      family: family
    } do
      vault1 = insert(:vault, family: family)
      vault2 = insert(:vault, family: family)

      result = Memories.list_vaults(family.id)
      assert [v2, v1] = result
      assert v2.id == vault2.id
      assert v1.id == vault1.id
    end

    test "list_vaults/1 does not return vaults from other families", %{family: family} do
      insert(:vault, family: family)
      other_family = insert(:family)
      insert(:vault, family: other_family)

      assert length(Memories.list_vaults(family.id)) == 1
    end

    test "get_vault!/1 returns the vault", %{family: family} do
      vault = insert(:vault, family: family)
      assert Memories.get_vault!(vault.id).id == vault.id
    end

    test "create_vault/2 with valid data creates a vault", %{family: family} do
      assert {:ok, %Vault{} = vault} = Memories.create_vault(family, %{name: "My Memories"})
      assert vault.name == "My Memories"
      assert vault.family_id == family.id
    end

    test "create_vault/2 with blank name returns error changeset", %{family: family} do
      assert {:error, %Ecto.Changeset{}} = Memories.create_vault(family, %{name: ""})
    end

    test "update_vault/2 updates the vault name", %{family: family} do
      vault = insert(:vault, family: family)
      assert {:ok, updated} = Memories.update_vault(vault, %{name: "New Name"})
      assert updated.name == "New Name"
    end

    test "delete_vault/1 deletes the vault", %{family: family} do
      vault = insert(:vault, family: family)
      assert {:ok, _} = Memories.delete_vault(vault)
      assert_raise Ecto.NoResultsError, fn -> Memories.get_vault!(vault.id) end
    end

    test "change_vault/2 returns a changeset", %{family: family} do
      vault = insert(:vault, family: family)
      assert %Ecto.Changeset{} = Memories.change_vault(vault, %{})
    end
  end
end
