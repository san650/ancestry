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

  describe "memories" do
    setup do
      org = insert(:organization)
      family = insert(:family, organization: org)
      vault = insert(:vault, family: family)
      account = insert(:account)
      person = insert(:person, organization: org)
      gallery = insert(:gallery, family: family)
      photo = insert(:photo, gallery: gallery)
      %{org: org, family: family, vault: vault, account: account, person: person, photo: photo}
    end

    test "list_memories/1 returns memories ordered by inserted_at desc", %{
      vault: vault,
      account: account
    } do
      m1 = insert(:memory, memory_vault: vault, account: account)
      m2 = insert(:memory, memory_vault: vault, account: account)
      result = Memories.list_memories(vault.id)
      assert [r2, r1] = result
      assert r2.id == m2.id
      assert r1.id == m1.id
    end

    test "get_memory!/1 returns the memory with preloads", %{vault: vault, account: account} do
      memory = insert(:memory, memory_vault: vault, account: account)
      result = Memories.get_memory!(memory.id)
      assert result.id == memory.id
    end

    test "create_memory/3 creates a memory and generates description", %{
      vault: vault,
      account: account
    } do
      attrs = %{name: "Summer Trip", content: "<div>We went to the beach.</div>"}
      assert {:ok, memory} = Memories.create_memory(vault, account, attrs)
      assert memory.name == "Summer Trip"
      assert memory.description == "We went to the beach."
      assert memory.inserted_by == account.id
    end

    test "create_memory/3 syncs mentions from content", %{
      vault: vault,
      account: account,
      person: person
    } do
      html =
        "<div>Remember <figure data-trix-attachment='{\"contentType\":\"application/vnd.memory-mention\"}'><span data-person-id=\"#{person.id}\">@#{person.given_name}</span></figure></div>"

      assert {:ok, memory} =
               Memories.create_memory(vault, account, %{name: "Test", content: html})

      memory = Memories.get_memory!(memory.id)
      assert length(memory.memory_mentions) == 1
      assert hd(memory.memory_mentions).person_id == person.id
    end

    test "create_memory/3 drops mentions for people outside the organization", %{
      vault: vault,
      account: account
    } do
      other_org = insert(:organization)
      other_person = insert(:person, organization: other_org)

      html =
        "<figure data-trix-attachment='{\"contentType\":\"application/vnd.memory-mention\"}'><span data-person-id=\"#{other_person.id}\">@Outsider</span></figure>"

      assert {:ok, memory} =
               Memories.create_memory(vault, account, %{name: "Test", content: html})

      memory = Memories.get_memory!(memory.id)
      assert memory.memory_mentions == []
    end

    test "create_memory/3 with blank name returns error", %{vault: vault, account: account} do
      assert {:error, %Ecto.Changeset{}} = Memories.create_memory(vault, account, %{name: ""})
    end

    test "update_memory/2 updates and re-syncs mentions", %{
      vault: vault,
      account: account,
      person: person
    } do
      {:ok, memory} =
        Memories.create_memory(vault, account, %{name: "Test", content: "<div>Hello</div>"})

      new_html =
        "<figure data-trix-attachment='{\"contentType\":\"application/vnd.memory-mention\"}'><span data-person-id=\"#{person.id}\">@#{person.given_name}</span></figure>"

      assert {:ok, updated} = Memories.update_memory(memory, %{content: new_html})
      updated = Memories.get_memory!(updated.id)
      assert length(updated.memory_mentions) == 1
    end

    test "delete_memory/1 deletes the memory", %{vault: vault, account: account} do
      {:ok, memory} = Memories.create_memory(vault, account, %{name: "Test", content: ""})
      assert {:ok, _} = Memories.delete_memory(memory)
      assert_raise Ecto.NoResultsError, fn -> Memories.get_memory!(memory.id) end
    end

    test "delete_vault/1 cascades to memories", %{vault: vault, account: account} do
      {:ok, memory} = Memories.create_memory(vault, account, %{name: "Test", content: ""})
      Memories.delete_vault(vault)
      assert_raise Ecto.NoResultsError, fn -> Memories.get_memory!(memory.id) end
    end
  end
end
