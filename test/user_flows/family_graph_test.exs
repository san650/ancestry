defmodule Web.UserFlows.FamilyGraphTest do
  use Web.E2ECase

  # View graph
  #
  # Given a family with people and a default person set
  # When the user navigates to the family show page
  # Then the graph canvas is rendered
  # And person cards with data-node-id attributes are present
  #
  # Focus person highlighted
  #
  # Given a family with a default person set
  # When the user navigates to the family show page
  # Then the default person's card has data-focus="true"
  #
  # Re-center on click
  #
  # Given a family with two people and a default focus person
  # When the user clicks a different person card
  # Then the URL params update to reflect the new person
  # And the clicked person's card now has data-focus="true"
  #
  # Navigate to person detail
  #
  # Given a focused person rendered in the graph
  # When the user looks at the person card
  # Then a link to the person's detail page is present

  setup do
    family = insert(:family, name: "Graph Family")
    org = Ancestry.Organizations.get_organization!(family.organization_id)

    alice =
      insert(:person,
        given_name: "Alice",
        surname: "Graph",
        gender: "female",
        organization: family.organization
      )

    bob =
      insert(:person,
        given_name: "Bob",
        surname: "Graph",
        gender: "male",
        organization: family.organization
      )

    charlie =
      insert(:person,
        given_name: "Charlie",
        surname: "Graph",
        organization: family.organization
      )

    for p <- [alice, bob, charlie], do: Ancestry.People.add_to_family(p, family)

    # Alice is parent of Charlie, Bob is partner of Alice
    Ancestry.Relationships.create_relationship(alice, charlie, "parent", %{role: "mother"})
    Ancestry.Relationships.create_relationship(alice, bob, "married", %{marriage_year: 1990})

    # Set Alice as the default focus person
    Ancestry.People.set_default_member(family.id, alice.id)

    %{family: family, org: org, alice: alice, bob: bob, charlie: charlie}
  end

  test "graph canvas renders with person cards", %{
    conn: conn,
    family: family,
    org: org,
    alice: alice
  } do
    # Given a family with people and a default person
    conn = log_in_e2e(conn)

    # When the user navigates to the family show page
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}")
      |> wait_liveview()

    # Then the graph canvas is rendered
    conn = conn |> assert_has(test_id("graph-canvas"))

    # And Alice's person card is present (default focus person)
    conn |> assert_has("[data-node-id='person-#{alice.id}']")
  end

  test "default focus person has data-focus=true", %{
    conn: conn,
    family: family,
    org: org,
    alice: alice
  } do
    # Given a family with Alice set as default person
    conn = log_in_e2e(conn)

    # When the user navigates to the family show page
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}")
      |> wait_liveview()

    # Then Alice's card has data-focus="true"
    conn |> assert_has("[data-node-id='person-#{alice.id}'][data-focus='true']")
  end

  test "clicking a different person re-centers the graph to that person", %{
    conn: conn,
    family: family,
    org: org,
    alice: alice,
    bob: bob
  } do
    # Given a family with Alice as default focus person
    conn = log_in_e2e(conn)

    # Navigate to the family show page — Alice is focused
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}")
      |> wait_liveview()

    conn = conn |> assert_has("[data-node-id='person-#{alice.id}'][data-focus='true']")

    # When the user clicks Bob's card (bob is in alice's graph as partner)
    conn =
      conn
      |> click("[data-node-id='person-#{bob.id}'] button")
      |> wait_liveview()

    # Then Bob's card now has data-focus="true"
    conn |> assert_has("[data-node-id='person-#{bob.id}'][data-focus='true']")
  end

  test "clicking the already-focused person navigates to their profile", %{
    conn: conn,
    family: family,
    org: org,
    alice: alice
  } do
    # Given Alice is the focused person
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}")
      |> wait_liveview()

    conn = conn |> assert_has("[data-node-id='person-#{alice.id}'][data-focus='true']")

    # When the user clicks Alice's card a second time (she's already focused)
    conn =
      conn
      |> click("[data-node-id='person-#{alice.id}'] button")
      |> wait_liveview()

    # Then the user is navigated to Alice's person detail page
    conn |> assert_has("h1", text: "Alice Graph")
  end

  test "person cards contain a link to the person detail page", %{
    conn: conn,
    family: family,
    org: org,
    alice: alice
  } do
    # Given Alice is rendered as the focused person in the graph
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}")
      |> wait_liveview()

    conn = conn |> assert_has("[data-node-id='person-#{alice.id}']")

    # Then Alice's card contains a link to her person detail page
    conn
    |> assert_has(
      "[data-node-id='person-#{alice.id}'] a[href='/org/#{org.id}/people/#{alice.id}']"
    )
  end

  test "navigating directly with ?person= param focuses that person", %{
    conn: conn,
    family: family,
    org: org,
    bob: bob
  } do
    # Given a URL with Bob's ID as the person param
    conn = log_in_e2e(conn)

    # When the user navigates directly with ?person=bob_id
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}?person=#{bob.id}")
      |> wait_liveview()

    # Then Bob's card is rendered with data-focus="true"
    conn |> assert_has("[data-node-id='person-#{bob.id}'][data-focus='true']")
  end
end
