defmodule Web.UserFlows.RenameOrganizationTest do
  use Web.E2ECase

  # Renaming an organization
  #
  # Given an existing organization
  # When the admin enters selection mode and selects one org
  # Then the selection bar shows "Rename" alongside "Delete"
  #
  # When the admin clicks "Rename"
  # Then selection mode exits and the rename modal opens with the current name
  #
  # When the admin changes the name and clicks "Save"
  # Then the modal closes and the updated name appears in the grid
  #
  # When the admin opens rename modal and clicks "Cancel"
  # Then the modal closes without changes
  #
  # When the admin submits an empty name
  # Then a validation error is shown
  #
  # When multiple orgs are selected
  # Then the "Rename" button is disabled
  #
  # When a non-admin enters selection mode
  # Then the "Rename" button is not shown
  setup do
    org = insert(:organization, name: "Original Name")
    org2 = insert(:organization, name: "Second Org")
    %{org: org, org2: org2}
  end

  test "admin renames organization via selection mode", %{conn: conn, org: org} do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org")
      |> wait_liveview()
      |> click(test_id("org-index-select-btn"))
      |> wait_liveview()
      |> click(test_id("org-card-#{org.id}"))
      |> wait_liveview()

    # Rename button should be visible
    conn = assert_has(conn, test_id("selection-bar-rename-btn"))

    # Click Rename — modal opens, selection mode exits
    conn =
      conn
      |> click(test_id("selection-bar-rename-btn"))
      |> wait_liveview()
      |> assert_has(test_id("org-rename-modal"))

    # Name input should be pre-filled
    conn = assert_has(conn, "input[name='organization[name]']", value: "Original Name")

    # Change name and save
    conn =
      conn
      |> fill_in("Organization name", with: "Updated Name")
      |> click_button(test_id("org-rename-submit-btn"), "Save")
      |> wait_liveview()

    # Modal should close, name should be updated
    conn
    |> refute_has(test_id("org-rename-modal"))
    |> assert_has("h2", text: "Updated Name")
    |> assert_has("[role=alert]", text: "Organization renamed")
  end

  test "cancel rename closes modal without changes", %{conn: conn, org: org} do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org")
      |> wait_liveview()
      |> click(test_id("org-index-select-btn"))
      |> wait_liveview()
      |> click(test_id("org-card-#{org.id}"))
      |> wait_liveview()
      |> click(test_id("selection-bar-rename-btn"))
      |> wait_liveview()
      |> assert_has(test_id("org-rename-modal"))

    # Cancel
    conn =
      conn
      |> click_button("Cancel")
      |> wait_liveview()

    conn
    |> refute_has(test_id("org-rename-modal"))
    |> assert_has("h2", text: "Original Name")
  end

  test "validation error on empty name", %{conn: conn, org: org} do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org")
      |> wait_liveview()
      |> click(test_id("org-index-select-btn"))
      |> wait_liveview()
      |> click(test_id("org-card-#{org.id}"))
      |> wait_liveview()
      |> click(test_id("selection-bar-rename-btn"))
      |> wait_liveview()

    # Clear name and submit
    conn =
      conn
      |> fill_in("Organization name", with: "")
      |> click_button(test_id("org-rename-submit-btn"), "Save")

    assert_has(conn, "p", text: "can't be blank")
  end

  test "rename button disabled when multiple orgs selected", %{conn: conn, org: org, org2: org2} do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org")
      |> wait_liveview()
      |> click(test_id("org-index-select-btn"))
      |> wait_liveview()
      |> click(test_id("org-card-#{org.id}"))
      |> click(test_id("org-card-#{org2.id}"))
      |> wait_liveview()

    assert_has(conn, test_id("selection-bar-rename-btn") <> "[disabled]")
  end

  test "rename button hidden for non-admin", %{conn: conn, org: org} do
    conn = log_in_e2e(conn, role: :editor, organization_ids: [org.id])

    conn =
      conn
      |> visit(~p"/org")
      |> wait_liveview()
      |> click(test_id("org-index-select-btn"))
      |> wait_liveview()
      |> click(test_id("org-card-#{org.id}"))
      |> wait_liveview()

    refute_has(conn, test_id("selection-bar-rename-btn"))
  end
end
