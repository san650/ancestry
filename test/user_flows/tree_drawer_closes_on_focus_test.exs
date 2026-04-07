defmodule Web.UserFlows.TreeDrawerClosesOnFocusTest do
  use Web.E2ECase

  # Force a mobile viewport so the nav drawer (lg:hidden aside) is the
  # actual UI in play. The desktop side panel is wrapped in
  # `hidden lg:block`, so on >=lg the drawer never opens.
  @moduletag browser_context_opts: [viewport: %{width: 414, height: 896}]

  setup do
    family = insert(:family, name: "Tree Drawer Family")
    org = Ancestry.Organizations.get_organization!(family.organization_id)

    alice =
      insert(:person,
        given_name: "Alice",
        surname: "Tester",
        organization: family.organization
      )

    bob =
      insert(:person,
        given_name: "Bob",
        surname: "Tester",
        organization: family.organization
      )

    Ancestry.People.add_to_family(alice, family)
    Ancestry.People.add_to_family(bob, family)

    %{org: org, family: family, alice: alice, bob: bob}
  end

  # Given a family with people
  # When the user opens the family show on mobile
  # And opens the nav drawer
  # And taps a person row inside the drawer's people list
  # Then the drawer closes
  # And the focused person is rendered in the tree behind it
  test "drawer closes when focusing a person from inside the drawer", %{
    conn: conn,
    org: org,
    family: family,
    alice: alice
  } do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}")
      |> wait_liveview()

    # Drawer starts closed: it has the `-translate-x-full` class and lacks
    # `translate-x-0`.
    conn = conn |> refute_has("aside#nav-drawer[class~='translate-x-0']")

    # Open the drawer via the hamburger button
    conn =
      conn
      |> click("button[aria-label='Open menu']")
      |> assert_has("aside#nav-drawer[class~='translate-x-0']")

    # Tap Alice's row inside the drawer. Both the drawer's people list
    # and the desktop side panel's people list render the same row in
    # the DOM, so we scope to the drawer container to disambiguate.
    conn =
      conn
      |> click("aside#nav-drawer " <> test_id("person-item-#{alice.id}") <> " button")
      |> wait_liveview()

    # The drawer should now be closed again.
    conn = conn |> refute_has("aside#nav-drawer[class~='translate-x-0']")

    # And Alice should be rendered in the tree behind it.
    conn |> assert_has("#tree-canvas", text: "Alice")
  end
end
