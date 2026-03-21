defmodule Web.UserFlows.DefaultPersonTest do
  use Web.E2ECase

  setup do
    family = insert(:family, name: "Tree Family")
    org = Ancestry.Organizations.get_organization!(family.organization_id)

    person_a =
      insert(:person, given_name: "Alice", surname: "Tree", organization: family.organization)

    person_b =
      insert(:person, given_name: "Bob", surname: "Tree", organization: family.organization)

    Ancestry.People.add_to_family(person_a, family)
    Ancestry.People.add_to_family(person_b, family)
    %{family: family, person_a: person_a, person_b: person_b, org: org}
  end

  test "set and clear default person for a family", %{conn: conn, person_a: person_a, org: org} do
    # Visit the family page — no default, should show person selector (not the tree)
    conn =
      conn
      |> visit(~p"/org/#{org.id}")
      |> wait_liveview()
      |> click_link("Tree Family")
      |> wait_liveview()

    # No tree should be rendered (no focus-person-card present)
    conn = conn |> refute_has("#focus-person-card")

    # Open Edit modal
    conn =
      conn
      |> click(test_id("family-edit-btn"))
      |> assert_has(test_id("family-edit-form"))
      |> assert_has(test_id("default-person-picker"))

    # Filter and select Alice as default
    conn = PhoenixTest.Playwright.type(conn, test_id("default-person-filter"), "Alice")

    conn =
      conn
      |> assert_has(test_id("default-person-option-#{person_a.id}"), timeout: 3_000)
      |> click(test_id("default-person-option-#{person_a.id}"))

    # Save
    conn =
      conn
      |> click_button(test_id("family-edit-save-btn"), "Save")
      |> wait_liveview()

    # Modal should close and tree should render immediately
    conn =
      conn
      |> refute_has(test_id("family-edit-form"))
      |> assert_has("#focus-person-card", timeout: 3_000)
      |> assert_has("[data-person-id='#{person_a.id}']")

    # Navigate away and back — tree should still be rendered
    conn =
      conn
      |> visit(~p"/org/#{org.id}")
      |> wait_liveview()
      |> click_link("Tree Family")
      |> wait_liveview()

    conn = conn |> assert_has("#focus-person-card", timeout: 3_000)
    conn = conn |> assert_has("[data-person-id='#{person_a.id}']")

    # Open Edit modal again and clear default
    conn =
      conn
      |> click(test_id("family-edit-btn"))
      |> assert_has(test_id("default-person-picker"))
      |> click(test_id("default-person-none"))
      |> click_button(test_id("family-edit-save-btn"), "Save")
      |> wait_liveview()

    # Modal should close and tree should be cleared immediately
    conn =
      conn
      |> refute_has(test_id("family-edit-form"))
      |> refute_has("#focus-person-card")

    # Navigate away and back — should still show no tree
    conn =
      conn
      |> visit(~p"/org/#{org.id}")
      |> wait_liveview()
      |> click_link("Tree Family")
      |> wait_liveview()

    conn |> refute_has("#focus-person-card")
  end
end
