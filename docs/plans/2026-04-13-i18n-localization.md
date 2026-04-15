# i18n & Localization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add full i18n support with en-US and es-UY locales — Gettext infrastructure, account locale field, Accept-Language detection, text extraction across all pages, Spanish translations, and language selection UI.

**Architecture:** Phoenix Gettext as the translation backend. A `Web.Locale` plug sets the locale for HTTP requests, and a `Web.SetLocale` on_mount hook sets it for LiveView processes. The account's `locale` field is the source of truth for logged-in users; session + Accept-Language is the fallback for anonymous visitors.

**Tech Stack:** Phoenix 1.8, Gettext 1.0, Ecto, LiveView 1.1

**Spec:** `docs/plans/2026-04-13-i18n-localization-design.md`

---

### Task 1: Fix Gettext Prerequisites

**Files:**
- Modify: `lib/web/gettext.ex:24`
- Modify: `config/config.exs` (after line 36)
- Rename: `priv/gettext/en/` → `priv/gettext/en-US/`

- [ ] **Step 1: Fix otp_app in Web.Gettext**

In `lib/web/gettext.ex`, change line 24:

```elixir
# FROM:
use Gettext.Backend, otp_app: :family
# TO:
use Gettext.Backend, otp_app: :ancestry
```

- [ ] **Step 2: Add Gettext config to config.exs**

In `config/config.exs`, add after line 36 (after the `live_view` config):

```elixir
# Gettext i18n configuration
config :ancestry, Web.Gettext,
  default_locale: "en-US",
  locales: ~w(en-US es-UY)
```

- [ ] **Step 3: Rename locale directory**

```bash
mv priv/gettext/en priv/gettext/en-US
```

- [ ] **Step 4: Verify compilation**

```bash
mix compile --warnings-as-errors
```
Expected: compiles without errors.

- [ ] **Step 5: Commit**

```bash
git add lib/web/gettext.ex config/config.exs priv/gettext/
git commit -m "Fix Gettext otp_app and configure i18n locales"
```

---

### Task 2: Account Locale Migration & Schema

**Files:**
- Create: `priv/repo/migrations/TIMESTAMP_add_locale_to_accounts.exs`
- Modify: `lib/ancestry/identity/account.ex:5-15` (schema fields), `:137-152` (admin_changeset)

- [ ] **Step 1: Create migration**

```bash
mix ecto.gen.migration add_locale_to_accounts
```

Write the migration:

```elixir
defmodule Ancestry.Repo.Migrations.AddLocaleToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :locale, :string, null: false, default: "en-US"
    end
  end
end
```

- [ ] **Step 2: Run migration**

```bash
mix ecto.migrate
```

- [ ] **Step 3: Add locale field to Account schema**

In `lib/ancestry/identity/account.ex`, add after line 15 (`field :avatar_status, :string`):

```elixir
field :locale, :string, default: "en-US"
```

- [ ] **Step 4: Add locale_changeset function**

In `lib/ancestry/identity/account.ex`, add after the `confirm_changeset/1` function (after line 127):

```elixir
@supported_locales ~w(en-US es-UY)

@doc """
Changeset for updating locale preference.
"""
def locale_changeset(account, attrs) do
  account
  |> cast(attrs, [:locale])
  |> validate_required([:locale])
  |> validate_inclusion(:locale, @supported_locales)
end
```

- [ ] **Step 5: Add :locale to admin_changeset cast list**

In `lib/ancestry/identity/account.ex`, change line 141:

```elixir
# FROM:
|> cast(attrs, [:email, :name, :role, :password])
# TO:
|> cast(attrs, [:email, :name, :role, :password, :locale])
```

Add locale validation after the `unique_constraint(:email)` line (after line 148):

```elixir
|> validate_inclusion(:locale, @supported_locales)
```

- [ ] **Step 6: Verify compilation and tests**

```bash
mix compile --warnings-as-errors && mix test test/ancestry/identity_test.exs
```

- [ ] **Step 7: Commit**

```bash
git add priv/repo/migrations/ lib/ancestry/identity/account.ex
git commit -m "Add locale field to accounts with en-US default"
```

---

### Task 3: Identity Context Functions

**Files:**
- Modify: `lib/ancestry/identity.ex` (add after `change_account_password` function, around line 155)

- [ ] **Step 1: Add change_account_locale and update_account_locale**

In `lib/ancestry/identity.ex`, add after the `update_account_password/2` function (after line 175):

```elixir
@doc """
Returns an `%Ecto.Changeset{}` for changing the account locale.

## Examples

    iex> change_account_locale(account)
    %Ecto.Changeset{data: %Account{}}

"""
def change_account_locale(account, attrs \\ %{}) do
  Account.locale_changeset(account, attrs)
end

@doc """
Updates the account locale.

## Examples

    iex> update_account_locale(account, %{locale: "es-UY"})
    {:ok, %Account{}}

"""
def update_account_locale(account, attrs) do
  account
  |> Account.locale_changeset(attrs)
  |> Repo.update()
end
```

- [ ] **Step 2: Verify compilation**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 3: Commit**

```bash
git add lib/ancestry/identity.ex
git commit -m "Add Identity context functions for locale management"
```

---

### Task 4: Locale Plug

**Files:**
- Create: `lib/web/plugs/locale.ex`
- Create: `test/web/plugs/locale_test.exs`

- [ ] **Step 1: Write the locale plug test**

Create `test/web/plugs/locale_test.exs`:

```elixir
defmodule Web.Plugs.LocaleTest do
  use Web.ConnCase, async: true

  alias Web.Plugs.Locale

  describe "call/2" do
    test "uses account locale when logged in", %{conn: conn} do
      account = insert(:account, locale: "es-UY")

      conn =
        conn
        |> assign(:current_scope, Ancestry.Identity.Scope.for_account(account))
        |> init_test_session(%{})
        |> Locale.call([])

      assert Gettext.get_locale(Web.Gettext) == "es-UY"
      assert get_session(conn, "locale") == "es-UY"
    end

    test "uses session locale when not logged in", %{conn: conn} do
      conn =
        conn
        |> assign(:current_scope, Ancestry.Identity.Scope.for_account(nil))
        |> init_test_session(%{"locale" => "es-UY"})
        |> Locale.call([])

      assert Gettext.get_locale(Web.Gettext) == "es-UY"
    end

    test "parses Accept-Language header for Spanish", %{conn: conn} do
      conn =
        conn
        |> assign(:current_scope, Ancestry.Identity.Scope.for_account(nil))
        |> init_test_session(%{})
        |> put_req_header("accept-language", "es-AR,es;q=0.9,en;q=0.8")
        |> Locale.call([])

      assert Gettext.get_locale(Web.Gettext) == "es-UY"
      assert get_session(conn, "locale") == "es-UY"
    end

    test "parses bare 'en' Accept-Language", %{conn: conn} do
      conn =
        conn
        |> assign(:current_scope, Ancestry.Identity.Scope.for_account(nil))
        |> init_test_session(%{})
        |> put_req_header("accept-language", "en")
        |> Locale.call([])

      assert Gettext.get_locale(Web.Gettext) == "en-US"
    end

    test "defaults to en-US when no locale info available", %{conn: conn} do
      conn =
        conn
        |> assign(:current_scope, Ancestry.Identity.Scope.for_account(nil))
        |> init_test_session(%{})
        |> Locale.call([])

      assert Gettext.get_locale(Web.Gettext) == "en-US"
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
mix test test/web/plugs/locale_test.exs
```
Expected: compilation error — `Web.Plugs.Locale` does not exist.

- [ ] **Step 3: Implement the locale plug**

Create `lib/web/plugs/locale.ex`:

```elixir
defmodule Web.Plugs.Locale do
  @moduledoc """
  Plug that sets the Gettext locale from the account, session, or Accept-Language header.
  """
  import Plug.Conn

  @supported_locales ~w(en-US es-UY)
  @default_locale "en-US"

  def init(opts), do: opts

  def call(conn, _opts) do
    locale = detect_locale(conn)
    Gettext.put_locale(Web.Gettext, locale)

    conn
    |> assign(:locale, locale)
    |> put_session("locale", locale)
  end

  defp detect_locale(conn) do
    from_account(conn) || from_session(conn) || from_accept_language(conn) || @default_locale
  end

  defp from_account(%{assigns: %{current_scope: %{account: %{locale: locale}}}})
       when is_binary(locale) and locale != "" do
    if locale in @supported_locales, do: locale
  end

  defp from_account(_conn), do: nil

  defp from_session(conn) do
    locale = get_session(conn, "locale")
    if locale in @supported_locales, do: locale
  end

  defp from_accept_language(conn) do
    case get_req_header(conn, "accept-language") do
      [header | _] -> parse_accept_language(header)
      _ -> nil
    end
  end

  defp parse_accept_language(header) do
    header
    |> String.split(",")
    |> Enum.map(&parse_language_tag/1)
    |> Enum.sort_by(fn {_lang, q} -> q end, :desc)
    |> Enum.find_value(fn {lang, _q} -> match_locale(lang) end)
  end

  defp parse_language_tag(tag) do
    case String.split(String.trim(tag), ";") do
      [lang] -> {String.trim(lang), 1.0}
      [lang, quality] ->
        q = case Regex.run(~r/q=([\d.]+)/, quality) do
          [_, val] -> String.to_float(normalize_float(val))
          _ -> 1.0
        end
        {String.trim(lang), q}
    end
  end

  defp normalize_float(val) do
    if String.contains?(val, "."), do: val, else: val <> ".0"
  end

  defp match_locale(lang) do
    downcased = String.downcase(lang)

    cond do
      downcased == "es-uy" -> "es-UY"
      String.starts_with?(downcased, "es") -> "es-UY"
      downcased == "en-us" -> "en-US"
      String.starts_with?(downcased, "en") -> "en-US"
      true -> nil
    end
  end
end
```

- [ ] **Step 4: Run tests**

```bash
mix test test/web/plugs/locale_test.exs
```
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/web/plugs/locale.ex test/web/plugs/locale_test.exs
git commit -m "Add locale detection plug with Accept-Language parsing"
```

---

### Task 5: SetLocale LiveView Hook

**Files:**
- Create: `lib/web/set_locale.ex`
- Create: `test/web/set_locale_test.exs`

- [ ] **Step 1: Write the hook test**

Create `test/web/set_locale_test.exs`:

```elixir
defmodule Web.SetLocaleTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest

  describe "on_mount" do
    test "sets locale from logged-in account", %{conn: conn} do
      account = insert(:account, locale: "es-UY")

      conn =
        conn
        |> log_in_account(account)

      {:ok, _view, _html} = live(conn, ~p"/accounts/settings")
      assert Gettext.get_locale(Web.Gettext) == "es-UY"
    end

    test "sets locale from session for logged-out user", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{"locale" => "es-UY"})

      {:ok, _view, _html} = live(conn, ~p"/accounts/log-in")
      assert Gettext.get_locale(Web.Gettext) == "es-UY"
    end

    test "defaults to en-US when no locale info", %{conn: conn} do
      {:ok, _view, _html} = live(conn, ~p"/accounts/log-in")
      assert Gettext.get_locale(Web.Gettext) == "en-US"
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

```bash
mix test test/web/set_locale_test.exs
```

- [ ] **Step 3: Implement SetLocale hook**

Create `lib/web/set_locale.ex`:

```elixir
defmodule Web.SetLocale do
  @moduledoc """
  LiveView on_mount hook that sets Gettext locale from account or session.
  """

  @default_locale "en-US"

  def on_mount(:default, _params, session, socket) do
    locale = detect_locale(socket, session)
    Gettext.put_locale(Web.Gettext, locale)
    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end

  defp detect_locale(socket, session) do
    from_account(socket) || from_session(session) || @default_locale
  end

  defp from_account(%{assigns: %{current_scope: %{account: %{locale: locale}}}})
       when is_binary(locale) and locale != "" do
    locale
  end

  defp from_account(_socket), do: nil

  defp from_session(session) do
    session["locale"]
  end
end
```

- [ ] **Step 4: Run tests**

```bash
mix test test/web/set_locale_test.exs
```

- [ ] **Step 5: Commit**

```bash
git add lib/web/set_locale.ex test/web/set_locale_test.exs
git commit -m "Add SetLocale LiveView on_mount hook"
```

---

### Task 6: Router & Session Integration

**Files:**
- Modify: `lib/web/router.ex:6-14` (browser pipeline), `:38-41,43-54,57-60,107-108,119-120` (live_sessions)
- Modify: `lib/web/account_auth.ex:132-149` (renew_session)

- [ ] **Step 1: Add Locale plug to browser pipeline**

In `lib/web/router.ex`, add after line 13 (`plug :fetch_current_scope_for_account`):

```elixir
plug Web.Plugs.Locale
```

- [ ] **Step 2: Add SetLocale hook to all five live_sessions**

In `lib/web/router.ex`, add `{Web.SetLocale, :default}` to the `on_mount` list of each live_session:

For `:default` (line 39), change to:
```elixir
on_mount: @sandbox_hooks ++ [{Web.AccountAuth, :require_authenticated}, {Web.SetLocale, :default}] do
```

For `:admin` (lines 44-48), change to:
```elixir
on_mount:
  @sandbox_hooks ++
    [
      {Web.AccountAuth, :require_authenticated},
      Permit.Phoenix.LiveView.AuthorizeHook,
      {Web.SetLocale, :default}
    ] do
```

For `:organization` (lines 58-60), change to:
```elixir
on_mount:
  @sandbox_hooks ++
    [{Web.AccountAuth, :require_authenticated}, Web.EnsureOrganization, {Web.SetLocale, :default}] do
```

For `:require_authenticated_account` (line 108), change to:
```elixir
on_mount: [{Web.AccountAuth, :require_authenticated}, {Web.SetLocale, :default}] do
```

For `:current_account` (line 120), change to:
```elixir
on_mount: [{Web.AccountAuth, :mount_current_scope}, {Web.SetLocale, :default}] do
```

- [ ] **Step 3: Preserve locale across session renewal**

In `lib/web/account_auth.ex`, replace lines 143-149 (the `renew_session/2` function that clears the session) with the commented-out version that preserves locale:

```elixir
defp renew_session(conn, _account) do
  delete_csrf_token()
  locale = get_session(conn, "locale")

  conn
  |> configure_session(renew: true)
  |> clear_session()
  |> put_session("locale", locale)
end
```

Also remove the commented-out example above it (lines 132-141) since we're now implementing it.

- [ ] **Step 4: Verify compilation and all tests pass**

```bash
mix compile --warnings-as-errors && mix test
```

- [ ] **Step 5: Commit**

```bash
git add lib/web/router.ex lib/web/account_auth.ex
git commit -m "Integrate locale plug and hook into router and session"
```

---

### Task 7: Account Settings Language Section

**Files:**
- Modify: `lib/web/live/account_live/settings.ex`

- [ ] **Step 1: Add language form assign in mount**

In `lib/web/live/account_live/settings.ex`, in the `mount/3` (no-token clause, line 107), add after line 116 (`|> assign(:email_form, to_form(email_changeset))`):

```elixir
|> assign(:locale_form, to_form(Identity.change_account_locale(account)))
```

- [ ] **Step 2: Add language section to render**

In `lib/web/live/account_live/settings.ex`, add after the password section closing `</div>` (after line 86), before the closing `</div>` tags:

```elixir
<div class="bg-ds-surface-card rounded-ds-sharp p-6 shadow-ds-ambient">
  <h2 class="font-ds-heading text-lg font-bold text-ds-on-surface mb-4">{gettext("Language")}</h2>
  <.form
    for={@locale_form}
    id="locale_form"
    phx-submit="update_locale"
    phx-change="validate_locale"
  >
    <.input
      field={@locale_form[:locale]}
      type="select"
      label={gettext("Language")}
      options={[{"English", "en-US"}, {"Español", "es-UY"}]}
    />
    <button
      type="submit"
      phx-disable-with={gettext("Saving...")}
      class="mt-4 px-6 py-2.5 bg-gradient-to-b from-ds-primary to-ds-primary-container text-ds-on-primary text-sm font-ds-body font-semibold rounded-ds-sharp transition-opacity hover:opacity-90 cursor-pointer"
    >
      {gettext("Save Language")}
    </button>
  </.form>
</div>
```

- [ ] **Step 3: Add validate_locale and update_locale event handlers**

In `lib/web/live/account_live/settings.ex`, add after the `update_password` handler (after line 178):

```elixir
def handle_event("validate_locale", %{"account" => locale_params}, socket) do
  locale_form =
    socket.assigns.current_scope.account
    |> Identity.change_account_locale(locale_params)
    |> Map.put(:action, :validate)
    |> to_form()

  {:noreply, assign(socket, locale_form: locale_form)}
end

def handle_event("update_locale", %{"account" => locale_params}, socket) do
  account = socket.assigns.current_scope.account

  case Identity.update_account_locale(account, locale_params) do
    {:ok, updated_account} ->
      Gettext.put_locale(Web.Gettext, updated_account.locale)

      scope = %{socket.assigns.current_scope | account: updated_account}

      {:noreply,
       socket
       |> assign(:current_scope, scope)
       |> assign(:locale_form, to_form(Identity.change_account_locale(updated_account)))
       |> put_flash(:info, gettext("Language updated successfully."))}

    {:error, changeset} ->
      {:noreply, assign(socket, locale_form: to_form(changeset, action: :insert))}
  end
end
```

- [ ] **Step 4: Verify the settings page loads**

```bash
mix test test/web/live/account_live/settings_test.exs 2>/dev/null || mix compile --warnings-as-errors
```

- [ ] **Step 5: Commit**

```bash
git add lib/web/live/account_live/settings.ex
git commit -m "Add language selection to account settings"
```

---

### Task 8: Admin Account Forms — Locale Field

**Files:**
- Modify: `lib/web/live/account_management_live/new.ex:155-160` (after role select)
- Modify: `lib/web/live/account_management_live/edit.ex:268-274` (after role select)

- [ ] **Step 1: Add locale select to admin new form**

In `lib/web/live/account_management_live/new.ex`, add after the role select (after line 160, the closing `/>` of the role input):

```elixir
<.input
  field={@form[:locale]}
  type="select"
  label={gettext("Language")}
  options={[{"English", "en-US"}, {"Español", "es-UY"}]}
/>
```

- [ ] **Step 2: Add locale select to admin edit form**

In `lib/web/live/account_management_live/edit.ex`, add after the role select (after line 274, the closing `/>` of the role input):

```elixir
<.input
  field={@form[:locale]}
  type="select"
  label={gettext("Language")}
  options={[{"English", "en-US"}, {"Español", "es-UY"}]}
/>
```

- [ ] **Step 3: Verify compilation**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 4: Commit**

```bash
git add lib/web/live/account_management_live/new.ex lib/web/live/account_management_live/edit.ex
git commit -m "Add locale select to admin account creation and edit forms"
```

---

### Task 9: Email Notification Localization

**Files:**
- Modify: `lib/ancestry/identity/account_notifier.ex`

- [ ] **Step 1: Add Gettext import and locale wrapper**

In `lib/ancestry/identity/account_notifier.ex`, add after line 2 (`import Swoosh.Email`):

```elixir
use Gettext, backend: Web.Gettext
```

- [ ] **Step 2: Wrap email text in gettext and add locale scoping**

Replace the `deliver_update_email_instructions/2` function (lines 24-39):

```elixir
def deliver_update_email_instructions(account, url) do
  locale = account.locale || "en-US"

  Gettext.with_locale(Web.Gettext, locale, fn ->
    deliver(account.email, gettext("Update email instructions"), """

    ==============================

    #{gettext("Hi %{email},", email: account.email)}

    #{gettext("You can change your email by visiting the URL below:")}

    #{url}

    #{gettext("If you didn't request this change, please ignore this.")}

    ==============================
    """)
  end)
end
```

Replace `deliver_magic_link_instructions/2` (lines 51-65):

```elixir
defp deliver_magic_link_instructions(account, url) do
  locale = account.locale || "en-US"

  Gettext.with_locale(Web.Gettext, locale, fn ->
    deliver(account.email, gettext("Log in instructions"), """

    ==============================

    #{gettext("Hi %{email},", email: account.email)}

    #{gettext("You can log into your account by visiting the URL below:")}

    #{url}

    #{gettext("If you didn't request this email, please ignore this.")}

    ==============================
    """)
  end)
end
```

Replace `deliver_confirmation_instructions/2` (lines 68-83):

```elixir
defp deliver_confirmation_instructions(account, url) do
  locale = account.locale || "en-US"

  Gettext.with_locale(Web.Gettext, locale, fn ->
    deliver(account.email, gettext("Confirmation instructions"), """

    ==============================

    #{gettext("Hi %{email},", email: account.email)}

    #{gettext("You can confirm your account by visiting the URL below:")}

    #{url}

    #{gettext("If you didn't create an account with us, please ignore this.")}

    ==============================
    """)
  end)
end
```

- [ ] **Step 3: Verify compilation**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 4: Commit**

```bash
git add lib/ancestry/identity/account_notifier.ex
git commit -m "Localize email notifications with Gettext"
```

---

### Task 10: Extract Strings — Layouts & Core Components

**Files:**
- Modify: `lib/web/components/layouts.ex`
- Modify: `lib/web/components/core_components.ex`
- Modify: `lib/web/components/layouts/root.html.heex`

- [ ] **Step 1: Wrap hardcoded strings in layouts.ex**

In `lib/web/components/layouts.ex`, wrap all hardcoded strings with `gettext()`:

- Line 56: `"Ancestry"` → `{gettext("Ancestry")}`
- Line 73: `"Organizations"` → `{gettext("Organizations")}`
- Line 79: `"Accounts"` → `{gettext("Accounts")}`
- Line 90: `"Settings"` → `{gettext("Settings")}`
- Line 99: `"Log out"` → `{gettext("Log out")}`

The flash_group strings on lines 143, 148, 155, 160 already use `gettext()` — no changes needed.

- [ ] **Step 2: Wrap hardcoded strings in core_components.ex**

In `lib/web/components/core_components.ex`:

- Line 368 already uses `gettext("Actions")` — no change needed.
- Line 74 already uses `gettext("close")` — no change needed.
- Scan for any other hardcoded user-facing strings and wrap them.

- [ ] **Step 3: Check root.html.heex for hardcoded strings**

Read `lib/web/components/layouts/root.html.heex` and wrap any user-facing text (e.g., `<html lang="en">` should use the locale assign if available).

- [ ] **Step 4: Verify compilation**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 5: Commit**

```bash
git add lib/web/components/
git commit -m "Extract layout and core component strings to Gettext"
```

---

### Task 11: Extract Strings — Auth Pages

**Files:**
- Modify: `lib/web/live/account_live/settings.ex`
- Modify: `lib/web/live/account_live/login.ex`
- Modify: `lib/web/live/account_live/registration.ex`
- Modify: `lib/web/live/account_live/confirmation.ex`
- Modify: `lib/web/account_auth.ex` (flash messages)

- [ ] **Step 1: Wrap strings in settings.ex**

All hardcoded strings in the render function and flash messages:
- `"Account Settings"` → `gettext("Account Settings")`
- `"Manage your account email address and password settings"` → `gettext("Manage your account email address and password settings")`
- `"Email"` (heading and label) → `gettext("Email")`
- `"Changing..."` → `gettext("Changing...")`
- `"Change Email"` → `gettext("Change Email")`
- `"Password"` → `gettext("Password")`
- `"New password"` → `gettext("New password")`
- `"Confirm new password"` → `gettext("Confirm new password")`
- `"Saving..."` → `gettext("Saving...")`
- `"Save Password"` → `gettext("Save Password")`
- Flash: `"Email changed successfully."` → `gettext("Email changed successfully.")`
- Flash: `"Email change link is invalid or it has expired."` → `gettext("Email change link is invalid or it has expired.")`
- Flash: `"A link to confirm your email change has been sent to the new address."` → `gettext("A link to confirm your email change has been sent to the new address.")`

- [ ] **Step 2: Wrap strings in login.ex**

Read `lib/web/live/account_live/login.ex` and wrap all user-facing strings.

- [ ] **Step 3: Wrap strings in registration.ex**

Read `lib/web/live/account_live/registration.ex` and wrap all user-facing strings.

- [ ] **Step 4: Wrap strings in confirmation.ex**

Read `lib/web/live/account_live/confirmation.ex` and wrap all user-facing strings.

- [ ] **Step 5: Wrap flash messages in account_auth.ex**

- Line 226: `"You must log in to access this page."` → `gettext("You must log in to access this page.")`
- Line 241: `"You must re-authenticate to access this page."` → `gettext("You must re-authenticate to access this page.")`
- Line 274: `"You must log in to access this page."` → `gettext("You must log in to access this page.")`

Add `use Gettext, backend: Web.Gettext` at the top of the module (after line 5, after `import Phoenix.Controller`).

- [ ] **Step 6: Verify compilation**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 7: Commit**

```bash
git add lib/web/live/account_live/ lib/web/account_auth.ex
git commit -m "Extract auth page strings to Gettext"
```

---

### Task 12: Extract Strings — Account Management Pages

**Files:**
- Modify: `lib/web/live/account_management_live/index.ex`
- Modify: `lib/web/live/account_management_live/new.ex`
- Modify: `lib/web/live/account_management_live/show.ex`
- Modify: `lib/web/live/account_management_live/edit.ex`

- [ ] **Step 1: Wrap all strings in account management LiveViews**

For each file, read it and wrap all user-facing strings (page titles, labels, buttons, flash messages, modal text, error messages) with `gettext()`.

Key strings to look for across all four files:
- Page titles: "Accounts", "New Account", "Edit Account"
- Labels: "Full name", "Email", "Password", "Confirm password", "Role", "Avatar", "Organizations", "New password"
- Role options: "Viewer", "Editor", "Admin" — wrap each display label
- Buttons: "Create Account", "Save Changes", "Cancel", "Remove", "View", "Edit"
- Flash messages: "Account created successfully", "Account updated successfully.", etc.
- Modal text: "Deactivate Account", "Are you sure...", "Reactivate Account"
- Status text: "Active", "Deactivated"
- Error messages: "You don't have permission to access this page", "You cannot change your own role.", "Cannot deactivate the last admin account."
- Upload errors: "File is too large (max 10MB)", "Only one avatar allowed", "Invalid file type"
- Placeholder: "Leave blank to keep current"
- Nav drawer labels: "Organizations", "Accounts"
- Aria labels: "Open menu"

- [ ] **Step 2: Verify compilation**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 3: Commit**

```bash
git add lib/web/live/account_management_live/
git commit -m "Extract account management strings to Gettext"
```

---

### Task 13: Extract Strings — Family Pages

**Files:**
- Modify: `lib/web/live/family_live/index.ex` and `index.html.heex`
- Modify: `lib/web/live/family_live/show.ex` and `show.html.heex`
- Modify: `lib/web/live/family_live/new.ex` and `new.html.heex`
- Modify: `lib/web/live/family_live/person_card_component.ex`
- Modify: `lib/web/live/family_live/people_list_component.ex`
- Modify: `lib/web/live/family_live/side_panel_component.ex`
- Modify: `lib/web/live/family_live/person_selector_component.ex`
- Modify: `lib/web/live/family_live/gallery_list_component.ex`
- Modify: `lib/web/live/family_live/vault_list_component.ex`

- [ ] **Step 1: Read and wrap strings in each family LiveView and component**

For each file, read it and wrap all user-facing strings with `gettext()`. This includes:
- Page titles, headings, empty state messages
- Button labels, link labels
- Flash messages
- Form labels, placeholders
- Modal text, confirmation dialogs
- Tooltip text
- Aria labels

- [ ] **Step 2: Verify compilation**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 3: Commit**

```bash
git add lib/web/live/family_live/
git commit -m "Extract family page strings to Gettext"
```

---

### Task 14: Extract Strings — Person Pages

**Files:**
- Modify: `lib/web/live/person_live/show.ex` and `show.html.heex`
- Modify: `lib/web/live/person_live/index.ex` and `index.html.heex`
- Modify: `lib/web/live/person_live/new.ex` and `new.html.heex`
- Modify: `lib/web/live/people_live/index.ex` and `index.html.heex`
- Modify: `lib/web/live/org_people_live/index.ex` and `index.html.heex`
- Modify: `lib/web/live/shared/person_form_component.ex` and `.html.heex`
- Modify: `lib/web/live/shared/add_relationship_component.ex`

- [ ] **Step 1: Read and wrap strings in each person-related LiveView and component**

Same pattern as Task 13. Include relationship type labels, form fields, empty states, etc.

- [ ] **Step 2: Verify compilation**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 3: Commit**

```bash
git add lib/web/live/person_live/ lib/web/live/people_live/ lib/web/live/org_people_live/ lib/web/live/shared/
git commit -m "Extract person page strings to Gettext"
```

---

### Task 15: Extract Strings — Gallery, Vault, Memory, Kinship, Org, Landing Pages

**Files:**
- Modify: `lib/web/live/gallery_live/show.ex` and `.html.heex`
- Modify: `lib/web/live/gallery_live/index.ex` and `.html.heex`
- Modify: `lib/web/live/vault_live/show.ex` and `.html.heex`
- Modify: `lib/web/live/memory_live/show.ex` and `show.html.heex`
- Modify: `lib/web/live/memory_live/form.ex` and `form.html.heex`
- Modify: `lib/web/live/kinship_live.ex` and `.html.heex`
- Modify: `lib/web/live/organization_live/index.ex` and `.html.heex`
- Modify: `lib/web/live/comments/photo_comments_component.ex`
- Modify: `lib/web/controllers/page_html/landing.html.heex`

- [ ] **Step 1: Read and wrap strings in each remaining LiveView/template**

Same pattern. Cover all user-facing text: headings, buttons, empty states, flash messages, form labels, etc.

- [ ] **Step 2: Verify compilation**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 3: Commit**

```bash
git add lib/web/live/gallery_live/ lib/web/live/vault_live/ lib/web/live/memory_live/ lib/web/live/kinship_live* lib/web/live/organization_live/ lib/web/live/comments/ lib/web/controllers/
git commit -m "Extract remaining page strings to Gettext"
```

---

### Task 16: Extract Strings — Context Modules

**Files:**
- Scan: `lib/ancestry/*.ex` for user-facing error/success messages
- Likely: `lib/ancestry/identity.ex`, `lib/ancestry/families.ex`, `lib/ancestry/galleries.ex`, `lib/ancestry/people.ex`

- [ ] **Step 1: Grep for hardcoded user-facing strings in context modules**

```bash
grep -rn '".*error\|".*success\|".*invalid\|".*cannot\|".*must\|".*already' lib/ancestry/ --include="*.ex" | grep -v _test | grep -v ".exs"
```

Wrap only strings that are surfaced to users (e.g., passed back in error tuples that LiveViews display). Do NOT wrap internal error atoms or log messages.

- [ ] **Step 2: Add `use Gettext, backend: Web.Gettext` to any context module that needs it**

- [ ] **Step 3: Verify compilation**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 4: Commit**

```bash
git add lib/ancestry/
git commit -m "Extract context module user-facing strings to Gettext"
```

---

### Task 17: Generate Translation Files & Write Spanish Translations

**Files:**
- Generate: `priv/gettext/default.pot`
- Generate: `priv/gettext/en-US/LC_MESSAGES/default.po`
- Generate: `priv/gettext/es-UY/LC_MESSAGES/default.po`
- Update: `priv/gettext/es-UY/LC_MESSAGES/errors.po`

- [ ] **Step 1: Extract and merge Gettext translations**

```bash
mix gettext.extract
mix gettext.merge priv/gettext
```

This creates `.pot` templates and merges into locale `.po` files.

- [ ] **Step 2: Verify en-US/LC_MESSAGES/default.po has all strings**

Open `priv/gettext/en-US/LC_MESSAGES/default.po` and verify all extracted strings are present. The `msgstr` values should be empty (Gettext uses the `msgid` as-is for the default locale).

- [ ] **Step 3: Write Spanish translations in es-UY/LC_MESSAGES/default.po**

Open `priv/gettext/es-UY/LC_MESSAGES/default.po` and fill in every `msgstr` with neutral Latin American Spanish translations. Guidelines:
- Standard "tú" conjugation, no voseo
- Neutral vocabulary understood across Latin America
- Informal but respectful tone

Key translations (reference, not exhaustive):

| English | Spanish |
|---------|---------|
| Account Settings | Configuración de la cuenta |
| Manage your account email address and password settings | Administra tu correo electrónico y contraseña |
| Email | Correo electrónico |
| Password | Contraseña |
| New password | Nueva contraseña |
| Confirm new password | Confirmar nueva contraseña |
| Change Email | Cambiar correo |
| Save Password | Guardar contraseña |
| Language | Idioma |
| Save Language | Guardar idioma |
| Language updated successfully. | Idioma actualizado correctamente. |
| Settings | Configuración |
| Log out | Cerrar sesión |
| Organizations | Organizaciones |
| Accounts | Cuentas |
| You must log in to access this page. | Debes iniciar sesión para acceder a esta página. |
| New Account | Nueva cuenta |
| Edit Account | Editar cuenta |
| Full name | Nombre completo |
| Role | Rol |
| Create Account | Crear cuenta |
| Save Changes | Guardar cambios |
| Cancel | Cancelar |
| Deactivate Account | Desactivar cuenta |
| Reactivate Account | Reactivar cuenta |
| Account created successfully | Cuenta creada correctamente |
| Account updated successfully. | Cuenta actualizada correctamente. |

- [ ] **Step 4: Write Spanish translations for es-UY/LC_MESSAGES/errors.po**

Translate Ecto validation error messages:
- "can't be blank" → "no puede estar vacío"
- "has already been taken" → "ya está en uso"
- "must have the @ sign and no spaces" → "debe contener el signo @ y no tener espacios"
- "does not match password" → "no coincide con la contraseña"
- "did not change" → "no ha cambiado"
- Etc.

- [ ] **Step 5: Verify extraction is complete**

```bash
mix gettext.extract --check-up-to-date
```

If this fails, there are `gettext()` calls that haven't been extracted yet. Fix and re-run.

- [ ] **Step 6: Commit**

```bash
git add priv/gettext/
git commit -m "Add Spanish (es-UY) translations for all UI strings"
```

---

### Task 18: E2E Tests

**Files:**
- Create: `test/user_flows/locale_settings_test.exs`

- [ ] **Step 1: Write E2E test for locale settings**

Create `test/user_flows/locale_settings_test.exs`:

```elixir
defmodule Web.UserFlows.LocaleSettingsTest do
  use Web.E2ECase

  # Given a logged-in user with locale en-US
  # When the user visits /accounts/settings
  # Then the language section is shown with "English" selected
  #
  # When the user changes the language to "Español"
  # And clicks "Save Language"
  # Then the page re-renders in Spanish
  # And a success flash is shown in Spanish
  #
  # Given an admin user
  # When the admin creates a new account with locale "es-UY"
  # Then the account is created with the Spanish locale
  #
  # When the admin edits the account's locale back to "en-US"
  # Then the account locale is updated

  test "user changes language in settings", %{conn: conn} do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/accounts/settings")
      |> wait_liveview()

    # Language section should be visible
    conn = assert_has(conn, "h2", text: "Language")

    # Change to Spanish
    conn =
      conn
      |> select(test_id("locale_form"), "Español")
      |> click_button("#locale_form button[type='submit']", "Save Language")
      |> wait_liveview()

    # Page should now show Spanish text
    conn
    |> assert_has("[role='alert']", text: "Idioma actualizado")
    |> assert_has("h2", text: "Idioma")
  end

  test "admin creates account with Spanish locale", %{conn: conn} do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/admin/accounts/new")
      |> wait_liveview()
      |> fill_in("Email", with: "spanish@example.com")
      |> fill_in("Password", with: "password123456")
      |> fill_in("Confirm password", with: "password123456")

    # Select Spanish locale
    conn =
      conn
      |> select(test_id("account-form"), "Español", from: "Language")
      |> click_button(test_id("account-submit-btn"), "Create Account")
      |> wait_liveview()

    conn
    |> assert_has("[role='alert']", text: "Account created")
  end

  test "admin edits account locale", %{conn: conn} do
    # Create a target account
    {:ok, target} =
      Ancestry.Identity.create_admin_account(
        %{email: "target@example.com", password: "password123456"},
        []
      )

    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/admin/accounts/#{target.id}/edit")
      |> wait_liveview()

    # Change locale to Spanish
    conn =
      conn
      |> select(test_id("account-form"), "Español", from: "Language")
      |> click_button(test_id("account-submit-btn"), "Save Changes")
      |> wait_liveview()

    conn
    |> assert_has("[role='alert']", text: "updated")
  end
end
```

- [ ] **Step 2: Write plug/hook integration tests**

The plug and hook tests were created in Tasks 4 and 5. Verify they still pass:

```bash
mix test test/web/plugs/locale_test.exs test/web/set_locale_test.exs
```

- [ ] **Step 3: Run all E2E tests**

```bash
mix test test/user_flows/locale_settings_test.exs
```

- [ ] **Step 4: Fix any failures and re-run**

- [ ] **Step 5: Commit**

```bash
git add test/user_flows/locale_settings_test.exs
git commit -m "Add E2E tests for locale settings and admin locale management"
```

---

### Task 19: Final Verification

- [ ] **Step 1: Run the full precommit check**

```bash
mix precommit
```

This runs compile (warnings-as-errors), removes unused deps, formats code, and runs all tests.

- [ ] **Step 2: Fix any issues found and re-run until clean**

- [ ] **Step 3: Verify Gettext extraction is up to date**

```bash
mix gettext.extract --check-up-to-date
```

- [ ] **Step 4: Final commit if any fixes were needed**

```bash
git add -A && git commit -m "Fix precommit issues for i18n implementation"
```
