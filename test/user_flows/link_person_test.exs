defmodule Web.UserFlows.LinkPersonTest do
  use Web.E2ECase

  setup do
    family = insert(:family, name: "Jones Family")
    org = Ancestry.Organizations.get_organization!(family.organization_id)

    person =
      insert(:person, given_name: "Bob", surname: "Williams", organization: family.organization)

    %{family: family, person: person, org: org}
  end

  test "link an existing person to a family", %{conn: conn, person: person, org: org} do
    conn = log_in_e2e(conn)

    # Visit families page and click the family
    conn =
      conn
      |> visit(~p"/org/#{org.id}")
      |> wait_liveview()
      |> click_link("Jones Family")
      |> wait_liveview()
      |> assert_has(test_id("family-empty-state"))

    # Click "Link existing person" button — modal should appear
    conn =
      conn
      |> click(test_id("person-link-btn"))
      |> assert_has(test_id("person-link-modal"))

    # Type the person's name to search — uses phx-keyup so we need actual typing
    conn = PhoenixTest.Playwright.type(conn, test_id("person-search-input"), "Bob")

    # Wait for debounced search results — person should appear
    conn =
      conn
      |> assert_has(test_id("person-link-result-#{person.id}"), timeout: 5_000)

    # Click the search result to link the person
    conn =
      conn
      |> click(test_id("person-link-result-#{person.id}"))
      |> wait_liveview()

    # Modal should close and person should be in the sidebar
    conn
    |> refute_has(test_id("person-link-modal"))
    |> assert_has(test_id("person-list"), text: "Williams")
  end
end
