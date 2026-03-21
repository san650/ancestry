defmodule Web.UserFlows.CreatePersonTest do
  use Web.E2ECase

  # Given an existing family
  # When the user navigates to the org families page
  # And clicks on the existing family
  # Then the family show screen is shown
  # And the empty state can be seen
  #
  # When the user clicks the add person button
  # Then the page navigates to the new member page
  #
  # When the user fills the form with the user information
  # And uploads a photo for the user
  # And clicks "Create"
  # Then the page navigates to the family show page
  # And the new person is listed on the sidebar
  setup do
    family = insert(:family, name: "Smith Family")
    org = Ancestry.Organizations.get_organization!(family.organization_id)
    %{family: family, org: org}
  end

  test "create a new person in a family", %{conn: conn, org: org} do
    # Visit families page and click the family
    conn =
      conn
      |> visit(~p"/org/#{org.id}")
      |> wait_liveview()
      |> click_link("Smith Family")
      |> wait_liveview()
      |> assert_has(test_id("family-empty-state"))

    # Click "Add member" button — should navigate to new member page
    conn =
      conn
      |> click(test_id("person-add-btn"))
      |> wait_liveview()
      |> assert_has(test_id("person-form"))

    # Fill in person details
    conn =
      conn
      |> fill_in("Given names", with: "Alice")
      |> fill_in("Surname", with: "Smith")

    # Upload a photo
    conn =
      conn
      |> upload_image(
        test_id("person-photo-input"),
        [Path.absname("test/fixtures/test_image.jpg")]
      )

    # Submit the form — should navigate back to family show
    conn =
      conn
      |> click_button(test_id("person-form-submit"), "Create")
      |> wait_liveview()

    # Person should appear in the sidebar
    conn
    |> assert_has(test_id("family-name"), text: "Smith Family")
    |> assert_has(test_id("person-list"), text: "Smith")
  end
end
