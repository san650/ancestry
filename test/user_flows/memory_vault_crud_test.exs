defmodule Web.UserFlows.MemoryVaultCrudTest do
  use Web.E2ECase

  setup do
    org = insert(:organization, name: "Vault Test Org")
    family = insert(:family, organization: org, name: "Vault Test Family")
    person = insert(:person, given_name: "Alice", surname: "Smith", organization: org)
    Ancestry.People.add_to_family(person, family)
    gallery = insert(:gallery, family: family, name: "Test Gallery")
    photo = insert(:photo, gallery: gallery, status: "processed")
    ensure_photo_file(photo)

    %{org: org, family: family, person: person, gallery: gallery, photo: photo}
  end

  # Given a family with no vaults
  # When the user visits the family page
  # And clicks the + button next to Memory Vaults
  # Then the "New Memory Vault" modal opens
  #
  # When the user fills in the vault name
  # And clicks "Create"
  # Then the modal closes
  # And the new vault appears in the vault list
  #
  # When the user clicks on the vault
  # Then the vault show page is displayed
  # And the empty state is shown
  #
  # When the user clicks "Add Memory"
  # Then the memory form page is displayed
  #
  # When the user fills in the memory name
  # And clicks "Create Memory"
  # Then the user is redirected to the vault show page
  # And the new memory card is shown
  #
  # When the user clicks on the memory card
  # Then the memory show page is displayed
  # And the memory name is visible
  #
  # When the user clicks the Edit button
  # Then the memory edit form is displayed
  #
  # When the user goes back to the vault page
  # And clicks the delete button on the vault
  # And confirms deletion
  # Then the user is redirected to the family page
  # And the vault is gone
  test "full vault and memory CRUD flow", %{conn: conn, org: org, family: family} do
    conn = log_in_e2e(conn)

    # Visit family page — should see empty vaults
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}")
      |> wait_liveview()
      |> assert_has(test_id("vaults-empty"))

    # Open new vault modal (target desktop sidebar — mobile drawer has a duplicate)
    conn =
      conn
      |> click("#side-panel-desktop-vault-list-new-btn")
      |> assert_has("#new-vault-modal")

    # Fill in name and create
    conn =
      conn
      |> fill_in("Vault name", with: "Summer Memories")
      |> click_button("Create")
      |> wait_liveview()

    # Modal should be closed, vault should appear
    conn =
      conn
      |> refute_has("#new-vault-modal")
      |> assert_has("a", text: "Summer Memories")

    # Get the vault from DB
    [vault] = Ancestry.Memories.list_vaults(family.id)

    # Click on the vault (desktop sidebar)
    conn =
      conn
      |> click("#side-panel-desktop-vault-list-#{vault.id}")
      |> wait_liveview()
      |> assert_has(test_id("vault-name"), text: "Summer Memories")
      |> assert_has(test_id("vault-empty-state"))

    # Click "Add Memory" — should see memory form
    conn =
      conn
      |> click(test_id("vault-add-memory-btn"))
      |> wait_liveview()
      |> assert_has(test_id("memory-form"))

    # Fill in memory name and save
    conn =
      conn
      |> fill_in("Name", with: "Beach Day")
      |> click(test_id("memory-save-btn"))
      |> wait_liveview()

    # Should be back on vault page with the memory card
    conn =
      conn
      |> assert_has(test_id("vault-name"), text: "Summer Memories")
      |> assert_has("h3", text: "Beach Day")

    # Get the memory from DB
    [memory] = Ancestry.Memories.list_memories(vault.id)

    # Click the memory card — should see the memory show page
    conn =
      conn
      |> click(test_id("memory-card-#{memory.id}"))
      |> wait_liveview()
      |> assert_has(test_id("memory-show-name"), text: "Beach Day")

    # Click Edit — should see the edit form
    conn =
      conn
      |> click(test_id("memory-edit-btn"))
      |> wait_liveview()
      |> assert_has(test_id("memory-form"))

    # Navigate back to vault page
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/vaults/#{vault.id}")
      |> wait_liveview()

    # Delete the vault
    conn =
      conn
      |> click(test_id("vault-delete-btn"))
      |> assert_has("#confirm-delete-vault-modal")
      |> click(test_id("confirm-delete-vault-btn"))
      |> wait_liveview()

    # Should be back on family page, vault gone
    conn
    |> refute_has("#side-panel-desktop-vault-list-#{vault.id}")
  end

  # Given a vault with a memory that has a cover photo
  # When the user visits the vault show page
  # Then the memory card renders with the cover photo
  # And no errors occur (Waffle needs gallery preloaded for URL generation)
  test "vault page renders memory with cover photo", %{
    conn: conn,
    org: org,
    family: family,
    photo: photo
  } do
    conn = log_in_e2e(conn)

    vault = insert(:vault, family: family, name: "Photo Vault")
    account = Ancestry.Repo.all(Ancestry.Identity.Account) |> List.first()

    {:ok, _memory} =
      Ancestry.Memories.create_memory(vault, account, %{
        name: "Memory With Photo",
        content: "<div>A memory with a cover photo</div>",
        cover_photo_id: photo.id
      })

    conn
    |> visit(~p"/org/#{org.id}/families/#{family.id}/vaults/#{vault.id}")
    |> wait_liveview()
    |> assert_has(test_id("vault-name"), text: "Photo Vault")
    |> assert_has("h3", text: "Memory With Photo")
  end

  # Given a vault with a memory
  # When the user visits the vault page
  # And clicks the memory card to open the show page
  # And clicks Edit to open the edit form
  # And clicks "Delete"
  # And confirms deletion
  # Then the user is redirected to the vault page
  # And the memory is gone
  test "delete a memory from edit page", %{conn: conn, org: org, family: family} do
    conn = log_in_e2e(conn)

    vault = insert(:vault, family: family, name: "Delete Memory Vault")
    account = Ancestry.Repo.all(Ancestry.Identity.Account) |> List.first()

    {:ok, memory} =
      Ancestry.Memories.create_memory(vault, account, %{
        name: "To Be Deleted",
        content: "<div>This will be deleted</div>"
      })

    # Visit vault page — memory should be visible
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/vaults/#{vault.id}")
      |> wait_liveview()
      |> assert_has("h3", text: "To Be Deleted")

    # Click memory card to open show page
    conn =
      conn
      |> click(test_id("memory-card-#{memory.id}"))
      |> wait_liveview()
      |> assert_has(test_id("memory-show-name"), text: "To Be Deleted")

    # Click Edit to open edit form
    conn =
      conn
      |> click(test_id("memory-edit-btn"))
      |> wait_liveview()
      |> assert_has(test_id("memory-form"))

    # Click delete button, confirm
    conn =
      conn
      |> click(test_id("memory-delete-btn"))
      |> assert_has("#confirm-delete-modal")
      |> click(test_id("confirm-delete-memory-btn"))
      |> wait_liveview()

    # Should be back on vault page, memory gone
    conn
    |> assert_has(test_id("vault-name"), text: "Delete Memory Vault")
    |> refute_has("h3", text: "To Be Deleted")
  end

  # Given a vault with memories
  # When the user visits the vault page
  # And clicks the delete vault button
  # And confirms deletion
  # Then the vault and all memories are deleted
  # And the user is redirected to the family page
  test "delete a vault with memories cascades", %{conn: conn, org: org, family: family} do
    conn = log_in_e2e(conn)

    vault = insert(:vault, family: family, name: "Cascade Vault")
    account = Ancestry.Repo.all(Ancestry.Identity.Account) |> List.first()

    {:ok, _} =
      Ancestry.Memories.create_memory(vault, account, %{
        name: "Memory One",
        content: "<div>First</div>"
      })

    {:ok, _} =
      Ancestry.Memories.create_memory(vault, account, %{
        name: "Memory Two",
        content: "<div>Second</div>"
      })

    # Visit vault page — both memories visible
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/vaults/#{vault.id}")
      |> wait_liveview()
      |> assert_has("h3", text: "Memory One")
      |> assert_has("h3", text: "Memory Two")

    # Delete the vault
    conn =
      conn
      |> click(test_id("vault-delete-btn"))
      |> assert_has("#confirm-delete-vault-modal")
      |> click(test_id("confirm-delete-vault-btn"))
      |> wait_liveview()

    # Should be back on family page — wait for it to load
    _conn =
      conn
      |> wait_liveview()

    # Verify DB cascade — vault and all memories deleted
    assert_raise Ecto.NoResultsError, fn -> Ancestry.Memories.get_vault!(vault.id) end
    assert Ancestry.Memories.list_memories(vault.id) == []
  end
end
