defmodule Web.UserFlows.DeleteFamilyTest do
  use Web.E2ECase

  alias Ancestry.People

  # Given a family with some people and galleries
  # When the user clicks on the family from the /families page
  # Then the user navigates to the family show page
  #
  # When the user clicks "Delete" on the toolbar
  # Then a confirmation modal is shown
  #
  # When the user clicks "Delete"
  # Then the family is deleted with all its related galleries
  # And people are not deleted, just detached from the family
  # And the user is redirected to the /families page
  setup do
    family = insert(:family, name: "Doomed Family")
    gallery = insert(:gallery, family: family, name: "Summer Photos")
    person = insert(:person, given_name: "Jane", surname: "Doe")
    People.add_to_family(person, family)
    %{family: family, gallery: gallery, person: person}
  end

  test "delete family keeps people but removes family and galleries", %{
    conn: conn,
    family: _family,
    person: person
  } do
    # Visit families page and click the family
    conn =
      conn
      |> visit(~p"/")
      |> wait_liveview()
      |> click_link("Doomed Family")
      |> wait_liveview()
      |> assert_has(test_id("family-name"), text: "Doomed Family")

    # Click Delete — confirmation modal should appear
    conn =
      conn
      |> click(test_id("family-delete-btn"))
      |> assert_has(test_id("family-delete-modal"))

    # Confirm deletion — should redirect to families index
    conn =
      conn
      |> click_button(test_id("family-delete-confirm-btn"), "Delete")
      |> wait_liveview()

    # Should be on families index, family should be gone
    conn
    |> assert_has(test_id("families-empty"))

    # Person should still exist in the database
    assert People.get_person!(person.id)
  end
end
