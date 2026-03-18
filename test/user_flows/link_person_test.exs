defmodule Web.UserFlows.LinkPersonTest do
  use Web.E2ECase

  # Given an existing family
  # And an existing person that's not associated to the family
  # When the user navigates to /families
  # And clicks on the existing family
  # Then the family show screen is shown
  # And the empty state can be seen
  #
  # When the user clicks the link people button
  # Then a modal is shown to search for an existing person
  #
  # When the user searches the existing user in the search form
  # Then the user appears as an option
  #
  # When the user selects the person from the search form
  # Then the person is added to the family
  # And the page navigates to the family show page
  # And the new person is listed on the sidebar
  setup do
    family = insert(:family, name: "Jones Family")
    person = insert(:person, given_name: "Bob", surname: "Williams")
    %{family: family, person: person}
  end

  test "link an existing person to a family", %{conn: conn, person: person} do
    # Visit families page and click the family
    conn =
      conn
      |> visit(~p"/")
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
