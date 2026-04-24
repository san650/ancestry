defmodule Web.UserFlows.FamilyMetricsTest do
  use Web.E2ECase

  setup do
    family = insert(:family, name: "Metrics Family")
    org = Ancestry.Organizations.get_organization!(family.organization_id)

    person_a =
      insert(:person,
        given_name: "Alice",
        surname: "Elder",
        organization: family.organization
      )

    person_b =
      insert(:person,
        given_name: "Bob",
        surname: "Elder",
        organization: family.organization
      )

    person_c =
      insert(:person,
        given_name: "Charlie",
        surname: "Elder",
        organization: family.organization
      )

    for p <- [person_a, person_b, person_c], do: Ancestry.People.add_to_family(p, family)

    # A gallery with photos
    gallery = insert(:gallery, family: family, name: "Summer 2025")
    insert(:photo, gallery: gallery) |> ensure_photo_file()
    insert(:photo, gallery: gallery) |> ensure_photo_file()

    %{family: family, org: org}
  end

  test "displays people and photo count metrics", %{
    conn: conn,
    family: family,
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
    conn
    |> assert_has(test_id("metric-photo-count"), text: "2")
  end
end
