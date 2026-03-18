defmodule Web.UserFlows.EditFamilyTest do
  use Web.E2ECase

  # Given a family
  # When the user clicks on the family from the /families page
  # Then the user navigates to the family show page
  #
  # When the user clicks "Edit" on the toolbar
  # Then a modal is shown to edit the family name
  #
  # When the user enters a new family name in the modal
  # And clicks "Save"
  # Then the modal closes and the family show page is visible
  # And the family name is updated
  setup do
    family = insert(:family, name: "Original Name")
    %{family: family}
  end

  test "edit family name via modal", %{conn: conn, family: _family} do
    # Visit families page and click the family
    conn =
      conn
      |> visit(~p"/")
      |> wait_liveview()
      |> click_link("Original Name")
      |> wait_liveview()
      |> assert_has(test_id("family-name"), text: "Original Name")

    # Click Edit — modal should appear
    conn =
      conn
      |> click(test_id("family-edit-btn"))
      |> assert_has(test_id("family-edit-form"))

    # Fill in new name and save
    conn =
      conn
      |> fill_in("Family name", with: "Updated Name")
      |> click_button(test_id("family-edit-save-btn"), "Save")
      |> wait_liveview()

    # Modal should close and name should be updated
    conn
    |> refute_has(test_id("family-edit-form"))
    |> assert_has(test_id("family-name"), text: "Updated Name")
  end
end
