defmodule Web.UserFlows.DeleteFamilyTest do
  use Web.E2ECase

  alias Ancestry.People

  setup do
    family = insert(:family, name: "Doomed Family")
    org = Ancestry.Organizations.get_organization!(family.organization_id)
    gallery = insert(:gallery, family: family, name: "Summer Photos")
    person = insert(:person, given_name: "Jane", surname: "Doe")
    People.add_to_family(person, family)
    %{family: family, gallery: gallery, person: person, org: org}
  end

  test "delete family keeps people but removes family and galleries", %{
    conn: conn,
    family: _family,
    person: person,
    org: org
  } do
    conn = log_in_e2e(conn)

    # Visit families page and click the family
    conn =
      conn
      |> visit(~p"/org/#{org.id}")
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
