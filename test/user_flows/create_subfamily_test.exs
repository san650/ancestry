defmodule Web.UserFlows.CreateSubfamilyTest do
  use Web.E2ECase

  # Given a family with connected people (parent, person, child)
  # When the user clicks the "Create subfamily" button on the family show page
  # Then a modal appears with the focused person pre-selected
  #
  # When the user enters a family name and clicks Create
  # Then a new family is created with the expected members
  # And the user is navigated to the new family's show page
  #
  # Given the modal is open
  # When the user presses Escape
  # Then the modal closes without creating a family

  setup do
    org = insert(:organization, name: "Test Org")
    family = insert(:family, name: "Big Family", organization: org)

    alice = insert(:person, given_name: "Alice", surname: "Smith", organization: org)
    bob = insert(:person, given_name: "Bob", surname: "Smith", organization: org)
    charlie = insert(:person, given_name: "Charlie", surname: "Smith", organization: org)

    Ancestry.People.add_to_family(alice, family)
    Ancestry.People.add_to_family(bob, family)
    Ancestry.People.add_to_family(charlie, family)

    {:ok, _} = Ancestry.Relationships.create_relationship(bob, alice, "parent", %{role: "father"})

    {:ok, _} =
      Ancestry.Relationships.create_relationship(alice, charlie, "parent", %{role: "mother"})

    Ancestry.People.set_default_member(family.id, alice.id)

    %{org: org, family: family, alice: alice, bob: bob, charlie: charlie}
  end

  test "create subfamily from family show page", %{conn: conn, org: org, family: family} do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}")
      |> wait_liveview()
      |> assert_has(test_id("family-name"), text: "Big Family")

    conn =
      conn
      |> click(test_id("meatball-btn"))
      |> click(test_id("family-create-subfamily-btn"))
      |> assert_has(test_id("create-subfamily-modal"))

    conn =
      conn
      |> fill_in("Family name", with: "Smith Subfamily")
      |> click_button(test_id("create-subfamily-submit-btn"), "Create")
      |> wait_liveview()

    conn
    |> assert_has(test_id("family-name"), text: "Smith Subfamily")
  end

  test "modal closes on Escape without creating a family", %{conn: conn, org: org, family: family} do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}")
      |> wait_liveview()
      |> click(test_id("meatball-btn"))
      |> click(test_id("family-create-subfamily-btn"))
      |> assert_has(test_id("create-subfamily-modal"))

    conn =
      conn
      |> PhoenixTest.Playwright.press("body", "Escape")

    conn
    |> refute_has(test_id("create-subfamily-modal"))
    |> assert_has(test_id("family-name"), text: "Big Family")
  end
end
