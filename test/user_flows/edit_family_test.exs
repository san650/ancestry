defmodule Web.UserFlows.EditFamilyTest do
  use Web.E2ECase

  setup do
    family = insert(:family, name: "Original Name")
    org = Ancestry.Organizations.get_organization!(family.organization_id)
    %{family: family, org: org}
  end

  test "edit family name via modal", %{conn: conn, family: _family, org: org} do
    conn = log_in_e2e(conn)

    # Visit families page and click the family
    conn =
      conn
      |> visit(~p"/org/#{org.id}")
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
