defmodule Web.UserFlows.CreateOrganizationTest do
  use Web.E2ECase

  # Given a system with an existing organization
  # When the user visits the organizations index page and clicks "New Organization"
  # Then the create modal appears
  #
  # When the user submits the form without a name
  # Then validation errors are shown
  #
  # When the user enters a name and submits
  # Then the modal closes and the new organization appears in the grid
  #
  # When the user clicks the backdrop
  # Then the modal closes without creating anything
  #
  # When the user clicks the Cancel button
  # Then the modal closes without creating anything
  #
  # When the user opens the modal, types a partial name, cancels, then reopens
  # Then the form is empty (no stale input or errors)
  setup do
    org = insert(:organization, name: "Existing Org")
    %{org: org}
  end

  test "create organization via modal", %{conn: conn, org: _org} do
    # Visit the organizations index page
    conn =
      conn
      |> visit(~p"/")
      |> wait_liveview()
      |> assert_has(test_id("org-new-btn"))

    # Click "New Organization" — modal should appear
    conn =
      conn
      |> click(test_id("org-new-btn"))
      |> assert_has(test_id("org-create-modal"))
      |> assert_has(test_id("org-create-form"))

    # Submit without a name — should show validation error
    conn =
      conn
      |> fill_in("Organization name", with: " ")
      |> click_button(test_id("org-create-submit-btn"), "Create")

    conn = assert_has(conn, "p", text: "can't be blank")

    # Fill in a valid name and submit
    conn =
      conn
      |> fill_in("Organization name", with: "New Test Org")
      |> click_button(test_id("org-create-submit-btn"), "Create")
      |> wait_liveview()

    # Modal should close and the new org should appear in the grid
    conn =
      conn
      |> refute_has(test_id("org-create-modal"))
      |> assert_has("h2", text: "New Test Org")

    # Verify flash message
    conn = assert_has(conn, ".alert", text: "Organization created")

    # Verify the existing org is still there
    assert_has(conn, "h2", text: "Existing Org")
  end

  test "dismiss modal via backdrop click", %{conn: conn} do
    conn =
      conn
      |> visit(~p"/")
      |> wait_liveview()
      |> click(test_id("org-new-btn"))
      |> assert_has(test_id("org-create-modal"))

    # Fill in a name but click the backdrop to dismiss
    # Use JS dispatch because the modal card overlaps the backdrop center,
    # preventing a normal Playwright click.
    conn =
      conn
      |> fill_in("Organization name", with: "Should Not Be Created")
      |> PhoenixTest.Playwright.evaluate("""
        document.querySelector("[data-testid='org-create-backdrop']").click();
      """)
      |> wait_liveview()

    # Modal should close, org should NOT be in the grid
    conn
    |> refute_has(test_id("org-create-modal"))
    |> refute_has("h2", text: "Should Not Be Created")
  end

  test "dismiss modal via cancel button", %{conn: conn} do
    conn =
      conn
      |> visit(~p"/")
      |> wait_liveview()
      |> click(test_id("org-new-btn"))
      |> assert_has(test_id("org-create-modal"))

    # Click cancel
    conn =
      conn
      |> click_button("Cancel")
      |> wait_liveview()

    conn
    |> refute_has(test_id("org-create-modal"))
  end

  test "reopening modal after cancel shows clean form", %{conn: conn} do
    conn =
      conn
      |> visit(~p"/")
      |> wait_liveview()
      |> click(test_id("org-new-btn"))
      |> assert_has(test_id("org-create-modal"))

    # Type something, then cancel
    conn =
      conn
      |> fill_in("Organization name", with: "Partial Name")
      |> click_button("Cancel")
      |> wait_liveview()
      |> refute_has(test_id("org-create-modal"))

    # Reopen — form should be clean
    conn =
      conn
      |> click(test_id("org-new-btn"))
      |> assert_has(test_id("org-create-modal"))

    # The input should be empty (value should be empty string)
    assert_has(conn, "input[name='organization[name]']", value: "")
  end
end
