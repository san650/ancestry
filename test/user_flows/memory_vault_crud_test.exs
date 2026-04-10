defmodule Web.UserFlows.MemoryVaultCrudTest do
  use Web.E2ECase

  setup do
    org = insert(:organization, name: "Vault Test Org")
    family = insert(:family, organization: org, name: "Vault Test Family")
    person = insert(:person, given_name: "Alice", surname: "Smith", organization: org)
    Ancestry.People.add_to_family(person, family)

    %{org: org, family: family, person: person}
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
  # Then the memory edit form is displayed
  # And the name field is pre-populated
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

    # Click the memory card — should see edit form
    conn =
      conn
      |> click(test_id("memory-card-#{memory.id}"))
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
end
