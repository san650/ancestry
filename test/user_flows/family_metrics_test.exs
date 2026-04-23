defmodule Web.UserFlows.FamilyMetricsTest do
  use Web.E2ECase

  setup do
    family = insert(:family, name: "Metrics Family")
    org = Ancestry.Organizations.get_organization!(family.organization_id)

    # 3-generation chain: grandpa -> parent -> child
    grandpa =
      insert(:person,
        given_name: "George",
        surname: "Elder",
        birth_year: 1940,
        organization: family.organization
      )

    parent =
      insert(:person,
        given_name: "Alice",
        surname: "Elder",
        birth_year: 1970,
        organization: family.organization
      )

    child =
      insert(:person,
        given_name: "Charlie",
        surname: "Elder",
        birth_year: 2000,
        organization: family.organization
      )

    for p <- [grandpa, parent, child], do: Ancestry.People.add_to_family(p, family)

    Ancestry.Relationships.create_relationship(grandpa, parent, "parent", %{role: "father"})
    Ancestry.Relationships.create_relationship(parent, child, "parent", %{role: "mother"})

    # A gallery with photos
    gallery = insert(:gallery, family: family, name: "Summer 2025")
    insert(:photo, gallery: gallery) |> ensure_photo_file()
    insert(:photo, gallery: gallery) |> ensure_photo_file()

    %{family: family, grandpa: grandpa, parent: parent, child: child, org: org}
  end

  test "displays metrics and navigates via person cards", %{
    conn: conn,
    family: family,
    grandpa: grandpa,
    child: child,
    org: org
  } do
    conn = log_in_e2e(conn)

    # Navigate to the family show page
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}")
      |> wait_liveview()

    # Verify people count
    conn =
      conn
      |> assert_has(test_id("metric-people-count"), text: "3")

    # Verify photo count
    conn =
      conn
      |> assert_has(test_id("metric-photo-count"), text: "2")

    # Verify generations metric
    conn =
      conn
      |> assert_has(test_id("metric-generations"), text: "3 generations")
      |> assert_has(test_id("metric-generations"), text: "George Elder")
      |> assert_has(test_id("metric-generations"), text: "Charlie Elder")

    # Verify oldest person
    conn =
      conn
      |> assert_has(test_id("metric-oldest-person"), text: "George Elder")
      |> assert_has(test_id("metric-oldest-person"), text: "years")

    # Click oldest person card — should load tree view for George
    conn =
      conn
      |> click(test_id("metric-oldest-person") <> ":visible button")
      |> wait_liveview()

    # Verify the tree loaded for grandpa
    conn =
      conn
      |> assert_has("[data-node-id='person-#{grandpa.id}']")

    # Navigate back to family show (no person focused)
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}")
      |> wait_liveview()

    # Click root ancestor in generations — the first button in the generations metric is the root
    conn =
      conn
      |> click(test_id("metric-generations") <> ":visible button:first-of-type")
      |> wait_liveview()

    conn =
      conn
      |> assert_has("[data-node-id='person-#{grandpa.id}']")

    # Navigate back and click leaf descendant — the last button in the generations metric
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}")
      |> wait_liveview()
      |> click(test_id("metric-generations") <> ":visible button:last-of-type")
      |> wait_liveview()

    conn
    |> assert_has("[data-node-id='person-#{child.id}']")
  end
end
