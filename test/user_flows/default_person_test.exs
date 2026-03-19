defmodule Web.UserFlows.DefaultPersonTest do
  use Web.E2ECase

  # Given a family with two members
  # When the user navigates to the family page
  # Then no tree is rendered (no default set)
  #
  # When the user clicks "Edit" on the toolbar
  # Then the Edit Family modal is shown with a default person picker
  #
  # When the user filters and selects a person as default
  # And clicks "Save"
  # Then the modal closes
  # And the tree is immediately rendered for the default person
  #
  # When the user navigates away and back to the family page
  # Then the tree is still rendered for the default person
  #
  # When the user clicks "Edit" again
  # And selects "None" as default person
  # And clicks "Save"
  # Then the modal closes
  # And the tree is immediately cleared
  #
  # When the user navigates away and back to the family page
  # Then the empty state / person selector is shown again
  setup do
    family = insert(:family, name: "Tree Family")
    person_a = insert(:person, given_name: "Alice", surname: "Tree")
    person_b = insert(:person, given_name: "Bob", surname: "Tree")
    Ancestry.People.add_to_family(person_a, family)
    Ancestry.People.add_to_family(person_b, family)
    %{family: family, person_a: person_a, person_b: person_b}
  end

  test "set and clear default person for a family", %{conn: conn, person_a: person_a} do
    # Visit the family page — no default, should show person selector (not the tree)
    conn =
      conn
      |> visit(~p"/")
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
      |> visit(~p"/")
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
      |> visit(~p"/")
      |> wait_liveview()
      |> click_link("Tree Family")
      |> wait_liveview()

    conn |> refute_has("#focus-person-card")
  end
end
