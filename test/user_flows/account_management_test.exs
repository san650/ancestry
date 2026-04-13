defmodule Web.UserFlows.AccountManagementTest do
  use Web.E2ECase

  # Given an admin user
  # When the admin visits /admin/accounts
  # Then the account list is shown
  #
  # When the admin clicks "New Account"
  # And fills in email, password, name, role
  # And clicks "Create Account"
  # Then the new account appears in the list
  #
  # When the admin clicks "View" on the new account
  # Then the account details are shown
  #
  # When the admin clicks "Deactivate"
  # Then a confirmation modal appears
  # When the admin confirms
  # Then the account is deactivated
  #
  # When the admin clicks "Reactivate"
  # Then a confirmation modal appears
  # When the admin confirms
  # Then the account is reactivated
  #
  # Given a non-admin user
  # When they visit /admin/accounts
  # Then they are redirected with a permission error

  setup do
    org = insert(:organization, name: "Test Org")
    %{org: org}
  end

  test "admin creates, views, deactivates, and reactivates an account", %{conn: conn} do
    conn = log_in_e2e(conn)

    # Visit account list
    conn =
      conn
      |> visit(~p"/admin/accounts")
      |> wait_liveview()
      |> assert_has(test_id("accounts-table"))

    # Navigate directly to the new account page
    conn =
      conn
      |> visit(~p"/admin/accounts/new")
      |> wait_liveview()
      |> assert_has(test_id("account-form"))

    # Fill form and submit
    conn =
      conn
      |> fill_in("Full name", with: "New User")
      |> fill_in("Email", with: "newuser@example.com")
      |> fill_in("Password", with: "password123456")
      |> fill_in("Confirm password", with: "password123456")
      |> click_button(test_id("account-submit-btn"), "Create Account")
      |> wait_liveview()

    # Should be back on accounts list with flash
    conn =
      conn
      |> assert_has("[role='alert']", text: "Account created")
      |> assert_has("td", text: "newuser@example.com")

    # Click View on the new account (scope to the row containing the email)
    conn =
      conn
      |> click("tr:has(td:text('newuser@example.com')) a", "View")
      |> wait_liveview()
      |> assert_has(test_id("account-email"), text: "newuser@example.com")
      |> assert_has(test_id("account-name"), text: "New User")

    # Deactivate
    conn =
      conn
      |> click(test_id("account-deactivate-btn"))
      |> assert_has(test_id("deactivate-modal"))
      |> click(test_id("deactivate-confirm-btn"))
      |> wait_liveview()
      |> assert_has("[role='alert']", text: "deactivated")
      |> assert_has(test_id("account-status"), text: "Deactivated")

    # Reactivate
    conn
    |> click(test_id("account-reactivate-btn"))
    |> assert_has(test_id("reactivate-modal"))
    |> click(test_id("reactivate-confirm-btn"))
    |> wait_liveview()
    |> assert_has("[role='alert']", text: "reactivated")
    |> assert_has(test_id("account-status"), text: "Active")
  end

  test "non-admin is redirected from /admin/accounts", %{conn: conn, org: org} do
    conn = log_in_e2e(conn, role: :editor, organization_ids: [org.id])

    conn
    |> visit(~p"/admin/accounts")
    |> wait_liveview()
    |> assert_has("[role='alert']", text: "permission")
  end

  test "admin cannot see deactivate button for own account", %{conn: conn} do
    conn = log_in_e2e(conn)

    # Visit the admin's own account show page.
    # The admin account was created by log_in_e2e; visit the list to find it.
    conn =
      conn
      |> visit(~p"/admin/accounts")
      |> wait_liveview()

    # Click View on the admin's own account (first in list)
    conn =
      conn
      |> click_link("a[href*='/admin/accounts/']", "View")
      |> wait_liveview()
      |> assert_has(test_id("account-detail"))

    # Deactivate button should not be present for own account
    refute_has(conn, test_id("account-deactivate-btn"))
  end

  test "non-admin sees only associated orgs", %{conn: conn, org: org} do
    _hidden_org = insert(:organization, name: "Hidden Org")

    conn = log_in_e2e(conn, role: :editor, organization_ids: [org.id])

    conn =
      conn
      |> visit(~p"/org")
      |> wait_liveview()

    conn
    |> assert_has("h2", text: "Test Org")
    |> refute_has("h2", text: "Hidden Org")
  end
end
