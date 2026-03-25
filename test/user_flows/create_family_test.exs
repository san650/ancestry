defmodule Web.UserFlows.CreateFamilyTest do
  use Web.E2ECase

  # Given a system with an organization
  # When the user visits the org page and clicks "New Family"
  # Then the "New Family" form is displayed.
  #
  # When the user writes a name for the family
  # And selects a cover photo
  # And clicks "Create"
  # Then a new family is created
  # And the application navigates automatically to the family show page
  # And the empty state is shown
  #
  # When the user clicks the navigate back arrow in the gallery
  # Then the grid with the list of families is shown
  #
  # When the user clicks on the family shown in the grid
  # Then the user can see the family show page
  setup do
    org = insert(:organization, name: "Test Org")
    %{org: org}
  end

  test "create a new family with cover photo and navigate back", %{conn: conn, org: org} do
    conn = log_in_e2e(conn)

    # Visit the org page — should see empty state
    conn =
      conn
      |> visit(~p"/org/#{org.id}")
      |> wait_liveview()
      |> assert_has(test_id("families-empty"))

    # Click "New Family" — should see the form
    conn =
      conn
      |> click_link(test_id("family-new-btn"), "New Family")
      |> wait_liveview()
      |> assert_has(test_id("family-create-form"))

    # Fill in the name and upload a cover photo
    conn =
      conn
      |> fill_in("Family name", with: "The Johnsons")
      |> upload_image(
        test_id("family-cover-input"),
        [Path.absname("test/fixtures/test_image.jpg")]
      )

    # Submit the form — should navigate to family show page
    conn =
      conn
      |> click_button("Create")
      |> wait_liveview()
      |> assert_has(test_id("family-name"), text: "The Johnsons")
      |> assert_has(test_id("family-empty-state"))

    # Click the back arrow — should see the family index
    conn =
      conn
      |> click(test_id("family-back-btn"))
      |> wait_liveview()
      |> refute_has(test_id("families-empty"))

    # Click the family card — should see the family show page again
    conn
    |> click_link("The Johnsons")
    |> wait_liveview()
    |> assert_has(test_id("family-name"), text: "The Johnsons")
  end
end
