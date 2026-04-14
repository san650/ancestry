defmodule Web.UserFlows.LocaleSettingsTest do
  use Web.E2ECase

  # Given a logged-in user with locale en-US
  # When the user visits /accounts/settings
  # Then the language section is shown with "English" selected
  #
  # When the user changes the language to "Español"
  # And clicks "Save Language"
  # Then a success flash is shown
  # And the page headings re-render in Spanish
  #
  # Given a logged-in admin
  # When the admin visits /admin/accounts/new
  # And fills in email, password, confirm password
  # And selects "Español" for the Language field
  # And clicks "Create Account"
  # Then the account is created successfully
  #
  # Given a logged-in admin and an existing account
  # When the admin visits /admin/accounts/:id/edit
  # And changes the Language to "Español"
  # And clicks "Save Changes"
  # Then the account is updated successfully

  test "user changes language in settings", %{conn: conn} do
    conn = log_in_e2e(conn)

    # Visit account settings
    conn =
      conn
      |> visit(~p"/accounts/settings")
      |> wait_liveview()

    # The language section should be visible with English selected
    conn =
      conn
      |> assert_has("h2", text: "Language")
      |> assert_has("h1", text: "Account Settings")

    # Change language to Español (exact: false needed because the label text
    # includes the select option text when the select is nested inside the label)
    conn =
      conn
      |> select("Language", exact: false, option: "Español")
      |> click_button("Save Language")
      |> wait_liveview()

    # The flash message appears in Spanish since the locale was just changed
    conn = assert_has(conn, "[role='alert']", text: "Idioma actualizado correctamente.")

    # Reload the page to verify the locale persists across page loads
    conn =
      conn
      |> visit(~p"/accounts/settings")
      |> wait_liveview()

    # After a fresh page load, headings should render in Spanish
    conn
    |> assert_has("h1", text: "Configuración de la cuenta")
    |> assert_has("h2", text: "Idioma")
  end

  test "admin creates account with Spanish locale", %{conn: conn} do
    conn = log_in_e2e(conn)

    # Navigate to new account page
    conn =
      conn
      |> visit(~p"/admin/accounts/new")
      |> wait_liveview()
      |> assert_has(test_id("account-form"))

    # Fill form with Spanish locale selected
    conn =
      conn
      |> fill_in("Email", with: "spanish-user@example.com")
      |> fill_in("Password", with: "password123456")
      |> fill_in("Confirm password", with: "password123456")
      |> select("Language", exact: false, option: "Español")
      |> click_button(test_id("account-submit-btn"), "Create Account")
      |> wait_liveview()

    # Should be back on accounts list with success flash
    conn
    |> assert_has("[role='alert']", text: "Account created")
    |> assert_has("td", text: "spanish-user@example.com")
  end

  test "admin edits account locale", %{conn: conn} do
    conn = log_in_e2e(conn)

    # Create an account first
    target = insert(:account, role: :editor)

    # Navigate to edit page
    conn =
      conn
      |> visit(~p"/admin/accounts/#{target.id}/edit")
      |> wait_liveview()
      |> assert_has(test_id("account-form"))

    # Change language to Español and save
    conn =
      conn
      |> select("Language", exact: false, option: "Español")
      |> click_button(test_id("account-submit-btn"), "Save Changes")
      |> wait_liveview()

    # Should redirect to account show with success flash
    conn
    |> assert_has("[role='alert']", text: "Account updated")
  end
end
