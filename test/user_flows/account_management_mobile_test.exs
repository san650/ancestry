defmodule Web.UserFlows.AccountManagementMobileTest do
  use Web.E2ECase

  # Force a mobile viewport so the nav drawer (lg:hidden) is the actual UI,
  # the desktop header is hidden, and the card layout renders instead of the table.
  @moduletag browser_context_opts: [viewport: %{width: 414, height: 896}]

  # Given an admin on mobile
  # When they visit the accounts list
  # Then accounts are shown as cards (not a table)
  # And the hamburger menu is visible
  #
  # When they tap the hamburger
  # Then the nav drawer slides in with Organizations and Accounts links
  #
  # When they tap Organizations
  # Then they navigate to the org index
  #
  # Given an admin on the account show page (mobile)
  # When they tap the hamburger
  # Then the nav drawer has Organizations and Accounts links
  #
  # Given an admin on the new account page (mobile)
  # When they tap the hamburger
  # Then the nav drawer has Organizations and Accounts links

  setup do
    org = insert(:organization, name: "Test Org")
    %{org: org}
  end

  test "mobile account list shows cards and hamburger menu navigates to orgs", %{conn: conn} do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/admin/accounts")
      |> wait_liveview()

    # Cards should be visible on mobile (not the table)
    conn = assert_has(conn, test_id("accounts-table"))

    # Table should be hidden on mobile (lg:block)
    refute_has(conn, "table")

    # Hamburger should be visible
    conn = assert_has(conn, "button[aria-label='Open menu']")

    # Tap hamburger — drawer should slide in
    conn =
      conn
      |> click("button[aria-label='Open menu']")
      |> assert_has("aside#nav-drawer")

    # Drawer should have Organizations and Accounts links
    conn =
      conn
      |> assert_has("aside#nav-drawer a[href='/org']", text: "Organizations")
      |> assert_has("aside#nav-drawer a[href='/admin/accounts']", text: "Accounts")

    # Tap Organizations — navigate away
    conn =
      conn
      |> click("aside#nav-drawer a[href='/org']")
      |> wait_liveview()

    # Should be on the organizations page
    assert_has(conn, "h1", text: "Organizations")
  end

  test "mobile show page hamburger has nav links", %{conn: conn} do
    conn = log_in_e2e(conn)

    # Create an account to view
    conn =
      conn
      |> visit(~p"/admin/accounts/new")
      |> wait_liveview()
      |> fill_in("Email", with: "mobile@example.com")
      |> fill_in("Password", with: "password123456")
      |> fill_in("Confirm password", with: "password123456")
      |> click_button(test_id("account-submit-btn"), "Create Account")
      |> wait_liveview()

    # Tap the card to navigate to show page (on mobile, cards are links)
    conn =
      conn
      |> click("a:has(p:text('mobile@example.com'))")
      |> wait_liveview()

    # Hamburger should be visible, back arrow hidden on mobile
    conn = assert_has(conn, "button[aria-label='Open menu']")

    # Tap hamburger — drawer should have both links
    conn
    |> click("button[aria-label='Open menu']")
    |> assert_has("aside#nav-drawer a[href='/org']", text: "Organizations")
    |> assert_has("aside#nav-drawer a[href='/admin/accounts']", text: "Accounts")
  end

  test "mobile new account page hamburger has nav links", %{conn: conn} do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/admin/accounts/new")
      |> wait_liveview()

    # Hamburger should be visible
    conn = assert_has(conn, "button[aria-label='Open menu']")

    # Tap hamburger
    conn
    |> click("button[aria-label='Open menu']")
    |> assert_has("aside#nav-drawer a[href='/org']", text: "Organizations")
    |> assert_has("aside#nav-drawer a[href='/admin/accounts']", text: "Accounts")
  end
end
