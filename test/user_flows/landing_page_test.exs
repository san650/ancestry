defmodule Web.UserFlows.LandingPageTest do
  use Web.E2ECase

  # Given an anonymous user
  # When they visit the root URL
  # Then the landing page is displayed with the headline, subtext, login button,
  # and "Registration coming soon" note
  #
  # When they click the "Log in" button
  # Then they are navigated to the login page
  #
  # Given a logged-in user
  # When they visit the root URL
  # Then they are redirected to the organizations page

  test "anonymous user sees landing page and can navigate to login", %{conn: conn} do
    conn =
      conn
      |> visit(~p"/")
      |> assert_has("h1", text: "Organize your family's photos and history.")
      |> assert_has("p", text: "Build galleries, connect people, and preserve what matters")
      |> assert_has("a", text: "Log in")
      |> assert_has("span", text: "Registration coming soon")

    conn
    |> click_link("Log in")
    |> wait_liveview()
    |> assert_has("h1", text: "Log in")
  end

  test "logged-in user is redirected from landing to organizations", %{conn: conn} do
    conn
    |> log_in_e2e()
    |> visit(~p"/")
    |> wait_liveview()
    |> assert_has("h1", text: "Organizations")
  end
end
