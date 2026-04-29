defmodule Web.UserFlows.OrgManagePeopleTest do
  use Web.E2ECase

  # Given an organization with families and people
  # When the user clicks "People" on the org landing page
  # Then the org people page is displayed with all people
  #
  # When the user types a search term
  # Then the table filters to matching people
  #
  # When the user clicks the "No family" chip
  # Then only people without family links are shown
  #
  # When the user clicks "Edit", selects people, and clicks "Delete"
  # Then a confirmation modal appears
  # When the user confirms
  # Then the selected people are permanently deleted
  #
  # When the user navigates to a person from the org people page
  # And clicks the back arrow
  # Then they return to the org people page

  setup do
    org = insert(:organization, name: "Test Org")
    family = insert(:family, name: "The Smiths", organization: org)

    alice =
      insert(:person,
        given_name: "Alice",
        surname: "Smith",
        birth_year: 1950,
        death_year: 2020,
        deceased: true,
        organization: org
      )

    bob =
      insert(:person,
        given_name: "Bob",
        surname: "Smith",
        birth_year: 1955,
        organization: org
      )

    # Orphan — not in any family
    orphan =
      insert(:person,
        given_name: "Orphan",
        surname: "Nobody",
        organization: org
      )

    for p <- [alice, bob], do: Ancestry.People.add_to_family(p, family)

    # Alice parent of Bob — 1 relationship each
    Ancestry.Relationships.create_relationship(alice, bob, "parent", %{role: "mother"})

    %{org: org, family: family, alice: alice, bob: bob, orphan: orphan}
  end

  test "navigate to org people page from family index", %{conn: conn, org: org} do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}")
      |> wait_liveview()
      |> click(test_id("kebab-btn"))
      |> click(test_id("org-people-btn"))
      |> wait_liveview()

    conn
    |> assert_has(test_id("org-people-table"))
    |> assert_has(test_id("org-people-table"), text: "Smith, Alice")
    |> assert_has(test_id("org-people-table"), text: "Smith, Bob")
    |> assert_has(test_id("org-people-table"), text: "Nobody, Orphan")
  end

  test "search filters the table", %{conn: conn, org: org} do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}/people")
      |> wait_liveview()

    conn = PhoenixTest.Playwright.type(conn, test_id("org-people-search") <> " input", "Smith")

    conn
    |> assert_has(test_id("org-people-table"), text: "Smith, Alice", timeout: 5_000)
    |> assert_has(test_id("org-people-table"), text: "Smith, Bob")
    |> refute_has(test_id("org-people-table"), text: "Nobody, Orphan")
  end

  test "no family chip filters to people without families", %{conn: conn, org: org} do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}/people")
      |> wait_liveview()
      |> click(test_id("org-people-no-family-chip"))
      |> wait_liveview()

    conn
    |> assert_has(test_id("org-people-table"), text: "Nobody, Orphan", timeout: 5_000)
    |> refute_has(test_id("org-people-table"), text: "Smith, Alice")
    |> refute_has(test_id("org-people-table"), text: "Smith, Bob")

    # Toggle off — all visible again
    conn =
      conn
      |> click(test_id("org-people-no-family-chip"))
      |> wait_liveview()

    conn
    |> assert_has(test_id("org-people-table"), text: "Smith, Alice", timeout: 5_000)
    |> assert_has(test_id("org-people-table"), text: "Nobody, Orphan")
  end

  test "bulk delete people", %{conn: conn, org: org, orphan: orphan, bob: bob} do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}/people")
      |> wait_liveview()

    # Enter edit mode
    conn =
      conn
      |> click(test_id("org-people-edit-btn"))
      |> wait_liveview()
      |> assert_has(test_id("org-people-checkbox-#{orphan.id}"), timeout: 5_000)

    # Select orphan and bob
    conn =
      conn
      |> click(test_id("org-people-checkbox-#{orphan.id}"))
      |> click(test_id("org-people-checkbox-#{bob.id}"))

    # Click delete
    conn =
      conn
      |> click(test_id("org-people-delete-btn"))
      |> wait_liveview()
      |> assert_has(test_id("org-people-confirm-delete-modal"))

    # Confirm
    conn =
      conn
      |> click(test_id("org-people-confirm-delete-btn"))
      |> wait_liveview()

    # Orphan and Bob gone, Alice remains
    conn
    |> assert_has(test_id("org-people-table"), text: "Smith, Alice", timeout: 5_000)
    |> refute_has(test_id("org-people-table"), text: "Smith, Bob")
    |> refute_has(test_id("org-people-table"), text: "Nobody, Orphan")
  end

  test "per-row delete button permanently deletes person", %{
    conn: conn,
    org: org,
    orphan: orphan
  } do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}/people")
      |> wait_liveview()

    # Click the per-row delete button on orphan
    conn =
      conn
      |> click(test_id("org-people-delete-person-#{orphan.id}"))
      |> wait_liveview()
      |> assert_has(test_id("org-people-confirm-delete-modal"))

    # Confirm
    conn =
      conn
      |> click(test_id("org-people-confirm-delete-btn"))
      |> wait_liveview()

    conn
    |> refute_has(test_id("org-people-table"), text: "Nobody, Orphan", timeout: 5_000)
    |> assert_has(test_id("org-people-table"), text: "Smith, Alice")
  end

  test "cancel delete dismisses modal", %{conn: conn, org: org, orphan: orphan} do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}/people")
      |> wait_liveview()

    # Enter edit mode and select orphan
    conn =
      conn
      |> click(test_id("org-people-edit-btn"))
      |> wait_liveview()
      |> assert_has(test_id("org-people-checkbox-#{orphan.id}"), timeout: 5_000)
      |> click(test_id("org-people-checkbox-#{orphan.id}"))
      |> click(test_id("org-people-delete-btn"))
      |> wait_liveview()
      |> assert_has(test_id("org-people-confirm-delete-modal"))

    # Cancel
    conn =
      conn
      |> click(test_id("org-people-cancel-delete-btn"))
      |> wait_liveview()

    conn
    |> refute_has(test_id("org-people-confirm-delete-modal"))
    |> assert_has(test_id("org-people-table"), text: "Nobody, Orphan")
  end

  test "back navigation from person show returns to org people", %{
    conn: conn,
    org: org,
    alice: alice
  } do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}/people")
      |> wait_liveview()

    # Click Alice's edit button to navigate to person show (with from_org param)
    conn =
      conn
      |> click(test_id("org-people-edit-person-#{alice.id}"))
      |> wait_liveview()

    # Should be on person show page (breadcrumb shows person name)
    conn = assert_has(conn, "h1", text: "Alice Smith")

    # Click "People" breadcrumb (navigates to org people page because from_org=true)
    conn =
      conn
      |> click_link("nav[aria-label='Breadcrumb']:visible a", "People")
      |> wait_liveview()

    # Should be back on org people page
    conn
    |> assert_has(test_id("org-people-table"))
  end
end
