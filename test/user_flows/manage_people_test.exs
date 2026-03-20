defmodule Web.UserFlows.ManagePeopleTest do
  use Web.E2ECase

  # Given a family with people (some with relationships, some without, one deceased)
  # When the user navigates to /families/:family_id
  # And clicks "Manage people" in the toolbar
  # Then the people table is shown with names, lifespans, relationship counts
  # And deceased people show the "deceased" indicator
  # And unconnected people show the "not connected" tag
  #
  # When the user types in the search box
  # Then the table narrows to matching people
  #
  # When the user clicks "Edit"
  # Then checkboxes appear on each row
  #
  # When the user selects 2 people and clicks "Remove from family"
  # Then a confirmation modal appears
  #
  # When the user confirms the removal
  # Then the people are removed from the table
  # And the page stays in edit mode
  # And a flash message confirms the removal
  #
  # When the user clicks "Done"
  # Then checkboxes disappear

  setup do
    family = insert(:family, name: "Test Family")

    alice =
      insert(:person,
        given_name: "Alice",
        surname: "Smith",
        birth_year: 1950,
        death_year: 2020,
        deceased: true
      )

    bob = insert(:person, given_name: "Bob", surname: "Smith", birth_year: 1955)
    charlie = insert(:person, given_name: "Charlie", surname: "Jones")
    diana = insert(:person, given_name: "Diana", surname: "Williams")

    for p <- [alice, bob, charlie, diana], do: Ancestry.People.add_to_family(p, family)

    # Alice is parent of Bob (both in family) = 1 relationship each
    Ancestry.Relationships.create_relationship(alice, bob, "parent", %{role: "mother"})
    # Alice and Charlie are partners (both in family) = 1 more for alice, 1 for charlie
    Ancestry.Relationships.create_relationship(alice, charlie, "partner")
    # Diana has no relationships = "not connected"

    %{family: family, alice: alice, bob: bob, charlie: charlie, diana: diana}
  end

  test "view people table with correct data", %{conn: conn, family: family} do
    conn =
      conn
      |> visit(~p"/families/#{family.id}/people")
      |> wait_liveview()

    # Verify table shows all 4 people
    conn
    |> assert_has(test_id("people-table"))
    |> assert_has(test_id("people-table"), text: "Smith, Alice")
    |> assert_has(test_id("people-table"), text: "Smith, Bob")
    |> assert_has(test_id("people-table"), text: "Jones, Charlie")
    |> assert_has(test_id("people-table"), text: "Williams, Diana")

    # Verify deceased indicator for Alice
    conn
    |> assert_has(test_id("people-table"), text: "deceased")

    # Verify "not connected" for Diana
    conn
    |> assert_has(test_id("people-table"), text: "not connected")
  end

  test "navigate from family show via toolbar", %{conn: conn, family: family} do
    conn =
      conn
      |> visit(~p"/families/#{family.id}")
      |> wait_liveview()
      |> click(test_id("family-manage-people-btn"))
      |> wait_liveview()

    conn
    |> assert_has(test_id("people-table"))
  end

  test "search filters the table", %{conn: conn, family: family} do
    conn =
      conn
      |> visit(~p"/families/#{family.id}/people")
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
    diana: diana
  } do
    conn =
      conn
      |> visit(~p"/families/#{family.id}/people")
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

  test "exit edit mode hides checkboxes", %{conn: conn, family: family, alice: alice} do
    conn =
      conn
      |> visit(~p"/families/#{family.id}/people")
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

  test "cancel removal dismisses modal", %{conn: conn, family: family, charlie: charlie} do
    conn =
      conn
      |> visit(~p"/families/#{family.id}/people")
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
end
