defmodule Web.UserFlows.ManagePeopleTest do
  use Web.E2ECase

  setup do
    family = insert(:family, name: "Test Family")
    org = Ancestry.Organizations.get_organization!(family.organization_id)

    alice =
      insert(:person,
        given_name: "Alice",
        surname: "Smith",
        birth_year: 1950,
        death_year: 2020,
        deceased: true,
        organization: family.organization
      )

    bob =
      insert(:person,
        given_name: "Bob",
        surname: "Smith",
        birth_year: 1955,
        organization: family.organization
      )

    charlie =
      insert(:person, given_name: "Charlie", surname: "Jones", organization: family.organization)

    diana =
      insert(:person, given_name: "Diana", surname: "Williams", organization: family.organization)

    for p <- [alice, bob, charlie, diana], do: Ancestry.People.add_to_family(p, family)

    # Alice is parent of Bob (both in family) = 1 relationship each
    Ancestry.Relationships.create_relationship(alice, bob, "parent", %{role: "mother"})
    # Alice and Charlie are partners (both in family) = 1 more for alice, 1 for charlie
    Ancestry.Relationships.create_relationship(alice, charlie, "relationship")
    # Diana has no relationships = warning icon

    %{family: family, alice: alice, bob: bob, charlie: charlie, diana: diana, org: org}
  end

  test "view people table with correct data", %{
    conn: conn,
    family: family,
    alice: alice,
    diana: diana,
    org: org
  } do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/people")
      |> wait_liveview()

    # Verify table shows all 4 people
    conn
    |> assert_has(test_id("people-table"))
    |> assert_has(test_id("people-table"), text: "Smith, Alice")
    |> assert_has(test_id("people-table"), text: "Smith, Bob")
    |> assert_has(test_id("people-table"), text: "Jones, Charlie")
    |> assert_has(test_id("people-table"), text: "Williams, Diana")

    # Verify Diana (0 relationships) shows warning icon
    conn
    |> assert_has(test_id("people-links-#{diana.id}") <> " .hero-exclamation-triangle")

    # Verify lifespan for Alice (deceased with both years)
    conn
    |> assert_has(test_id("people-table"), text: "b. 1950")
    |> assert_has(test_id("people-table"), text: "d. 2020")

    # Verify deceased indicator has title attribute
    conn
    |> assert_has(test_id("people-row-#{alice.id}") <> " [title='Deceased']")
  end

  test "navigate from family show via toolbar", %{conn: conn, family: family, org: org} do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}")
      |> wait_liveview()
      |> click(test_id("meatball-btn"))
      |> click(test_id("family-manage-people-btn"))
      |> wait_liveview()

    conn
    |> assert_has(test_id("people-table"))
  end

  test "search filters the table", %{conn: conn, family: family, org: org} do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/people")
      |> wait_liveview()

    # Search for "Smith" -- should show Alice and Bob, hide Charlie and Diana
    conn = PhoenixTest.Playwright.type(conn, test_id("people-search") <> " input", "Smith")

    conn
    |> assert_has(test_id("people-table"), text: "Smith, Alice", timeout: 5_000)
    |> assert_has(test_id("people-table"), text: "Smith, Bob")
    |> refute_has(test_id("people-table"), text: "Jones, Charlie")
    |> refute_has(test_id("people-table"), text: "Williams, Diana")
  end

  test "edit mode, select, and remove people", %{
    conn: conn,
    family: family,
    charlie: charlie,
    diana: diana,
    org: org
  } do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/people")
      |> wait_liveview()

    # Enter edit mode
    conn =
      conn
      |> click(test_id("people-edit-btn"))
      |> wait_liveview()

    # Checkboxes should appear
    conn =
      conn
      |> assert_has(test_id("people-checkbox-#{charlie.id}"), timeout: 5_000)
      |> assert_has(test_id("people-checkbox-#{diana.id}"))

    # Select Charlie and Diana
    conn =
      conn
      |> click(test_id("people-checkbox-#{charlie.id}"))
      |> click(test_id("people-checkbox-#{diana.id}"))

    # Click remove
    conn =
      conn
      |> click(test_id("people-remove-btn"))
      |> wait_liveview()

    # Confirmation modal should appear
    conn =
      conn
      |> assert_has(test_id("people-confirm-remove-btn"))

    # Confirm removal
    conn =
      conn
      |> click(test_id("people-confirm-remove-btn"))
      |> wait_liveview()

    # Charlie and Diana should be gone, Alice and Bob remain
    conn =
      conn
      |> assert_has(test_id("people-table"), text: "Smith, Alice", timeout: 5_000)
      |> assert_has(test_id("people-table"), text: "Smith, Bob")
      |> refute_has(test_id("people-table"), text: "Jones, Charlie")
      |> refute_has(test_id("people-table"), text: "Williams, Diana")

    # Should still be in edit mode (button says "Done")
    conn
    |> assert_has(test_id("people-edit-btn"), text: "Done")
  end

  test "exit edit mode hides checkboxes", %{conn: conn, family: family, alice: alice, org: org} do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/people")
      |> wait_liveview()

    # Enter edit mode
    conn =
      conn
      |> click(test_id("people-edit-btn"))
      |> wait_liveview()

    # Checkbox visible
    conn =
      conn
      |> assert_has(test_id("people-checkbox-#{alice.id}"), timeout: 5_000)

    # Exit edit mode by clicking "Done"
    conn =
      conn
      |> click(test_id("people-edit-btn"))
      |> wait_liveview()

    # Checkboxes should be gone
    conn
    |> refute_has(test_id("people-checkbox-#{alice.id}"))

    # Edit button should say "Edit" again
    conn
    |> assert_has(test_id("people-edit-btn"), text: "Edit")
  end

  test "cancel removal dismisses modal", %{
    conn: conn,
    family: family,
    charlie: charlie,
    org: org
  } do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/people")
      |> wait_liveview()

    # Enter edit mode and select Charlie
    conn =
      conn
      |> click(test_id("people-edit-btn"))
      |> wait_liveview()
      |> assert_has(test_id("people-checkbox-#{charlie.id}"), timeout: 5_000)
      |> click(test_id("people-checkbox-#{charlie.id}"))

    # Click remove
    conn =
      conn
      |> click(test_id("people-remove-btn"))
      |> wait_liveview()

    # Modal appears
    conn =
      conn
      |> assert_has(test_id("people-confirm-remove-modal"))

    # Cancel
    conn =
      conn
      |> click(test_id("people-cancel-remove-btn"))
      |> wait_liveview()

    # Modal should be gone, Charlie still in the table
    conn
    |> refute_has(test_id("people-confirm-remove-modal"))
    |> assert_has(test_id("people-table"), text: "Jones, Charlie")
  end

  # --- New tests for grid table features ---

  test "unlinked chip filters to people with 0 relationships", %{
    conn: conn,
    family: family,
    org: org
  } do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/people")
      |> wait_liveview()

    # Click the Unlinked chip
    conn =
      conn
      |> click(test_id("people-unlinked-chip"))
      |> wait_liveview()

    # Only Diana (0 relationships) should be visible
    conn
    |> assert_has(test_id("people-table"), text: "Williams, Diana", timeout: 5_000)
    |> refute_has(test_id("people-table"), text: "Smith, Alice")
    |> refute_has(test_id("people-table"), text: "Smith, Bob")
    |> refute_has(test_id("people-table"), text: "Jones, Charlie")

    # Click again to deactivate
    conn =
      conn
      |> click(test_id("people-unlinked-chip"))
      |> wait_liveview()

    # All people should be visible again
    conn
    |> assert_has(test_id("people-table"), text: "Smith, Alice", timeout: 5_000)
    |> assert_has(test_id("people-table"), text: "Williams, Diana")
  end

  test "unlinked filter composes with text search", %{
    conn: conn,
    family: family,
    org: org
  } do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/people")
      |> wait_liveview()

    # Activate unlinked filter
    conn =
      conn
      |> click(test_id("people-unlinked-chip"))
      |> wait_liveview()
      |> assert_has(test_id("people-table"), text: "Williams, Diana", timeout: 5_000)

    # Search for "Smith" — no unlinked person has surname Smith
    conn = PhoenixTest.Playwright.type(conn, test_id("people-search") <> " input", "Smith")

    conn
    |> refute_has(test_id("people-table"), text: "Williams, Diana", timeout: 5_000)
    |> refute_has(test_id("people-table"), text: "Smith, Alice")
  end

  test "per-row unlink button removes person from family", %{
    conn: conn,
    family: family,
    diana: diana,
    org: org
  } do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/people")
      |> wait_liveview()

    # Click the unlink button on Diana's row
    conn =
      conn
      |> click(test_id("people-unlink-#{diana.id}"))
      |> wait_liveview()

    # Confirmation modal should appear
    conn =
      conn
      |> assert_has(test_id("people-confirm-remove-modal"))

    # Confirm removal
    conn =
      conn
      |> click(test_id("people-confirm-remove-btn"))
      |> wait_liveview()

    # Diana should be gone
    conn
    |> refute_has(test_id("people-table"), text: "Williams, Diana", timeout: 5_000)
    |> assert_has(test_id("people-table"), text: "Smith, Alice")
  end

  test "estimated age displays correctly", %{conn: conn, family: family, org: org} do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/people")
      |> wait_liveview()

    # Alice: deceased, birth_year: 1950, death_year: 2020 -> ~70 (stable)
    conn
    |> assert_has(test_id("people-table"), text: "~70")

    # Bob: alive, birth_year: 1955 -> dynamic age
    expected_bob_age = Date.utc_today().year - 1955

    conn
    |> assert_has(test_id("people-table"), text: "~#{expected_bob_age}")
  end

  test "per-row unlink buttons hidden in edit mode", %{
    conn: conn,
    family: family,
    diana: diana,
    org: org
  } do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/people")
      |> wait_liveview()

    # Unlink button visible in normal mode
    conn
    |> assert_has(test_id("people-unlink-#{diana.id}"))

    # Enter edit mode
    conn =
      conn
      |> click(test_id("people-edit-btn"))
      |> wait_liveview()

    # Unlink button should be hidden
    conn
    |> refute_has(test_id("people-unlink-#{diana.id}"))

    # Exit edit mode
    conn =
      conn
      |> click(test_id("people-edit-btn"))
      |> wait_liveview()

    # Unlink button should be visible again
    conn
    |> assert_has(test_id("people-unlink-#{diana.id}"))
  end
end
