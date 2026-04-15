# i18n & Localization Design

**Date:** 2026-04-13
**Status:** Approved

## Overview

Add full internationalization (i18n) support to the Ancestry app with English (en-US, default) and Latin American Spanish (es-UY) as the two supported locales. All user-facing text across the entire app is extracted into Gettext and translated. Users can select their language in account settings, and logged-out visitors get automatic language detection from the HTTP `Accept-Language` header.

## Locale Values

- `"en-US"` — English (default)
- `"es-UY"` — Latin American Spanish (neutral, no voseo, no regional slang, standard "tú" form)

## 1. Gettext Configuration & Locale Infrastructure

### Prerequisites

- **Fix `otp_app` in `Web.Gettext`:** Change `otp_app: :family` to `otp_app: :ancestry`. This is a required fix — the current value is wrong and will prevent all translations from loading.
- **Rename existing locale directory:** Rename `priv/gettext/en/` to `priv/gettext/en-US/` so the existing Ecto error translations continue to work with the new locale code.

### Gettext config (`config/config.exs`)

```elixir
config :ancestry, Web.Gettext,
  default_locale: "en-US",
  locales: ~w(en-US es-UY)
```

### Locale plug (`Web.Locale`)

Runs in the browser pipeline after session/auth plugs. Priority order:

1. Logged-in account's `locale` field
2. Session `"locale"` value
3. `Accept-Language` header (simple parser, no library)
4. Fallback: `"en-US"`

Calls `Gettext.put_locale/1`, stores resolved locale in `conn.assigns.locale` and the session.

### Accept-Language matching

- `en-US`, `en-*`, bare `en` → `"en-US"`
- `es-UY`, `es-*`, bare `es` → `"es-UY"`
- Anything else → `"en-US"`

### Session preservation on login

`Web.AccountAuth.renew_session/2` calls `clear_session()` on login. The locale stored in session would be lost. Uncomment and use the existing commented-out locale preservation code in `renew_session/2` to carry the locale across the session renewal.

### LiveView on_mount hook (`Web.SetLocale`)

- On `mount`: reads locale from `socket.assigns.current_scope.account.locale` (logged in) or session `"locale"` (logged out)
- **Must handle nil:** `current_scope` or `current_scope.account` may be nil in unauthenticated `live_session` blocks (e.g., `:current_account` for the login page). Fall back to session locale or `"en-US"`.
- Calls `Gettext.put_locale/1`
- Added to **all five** `live_session` blocks in `router.ex`: `:default`, `:admin`, `:organization`, `:require_authenticated_account`, `:current_account`

## 2. Account Schema & Database Changes

### Migration

- Add `locale` column to `accounts` table: `string`, not null, default `"en-US"`
- Backfills all existing accounts to `"en-US"`

### Schema (`Account`)

- Add `field :locale, :string, default: "en-US"`
- Validate inclusion in `~w(en-US es-UY)` in changeset

### Changesets

- **`admin_changeset/3`:** Add `:locale` to the cast list (currently casts `[:email, :name, :role, :password]`). This enables admin creation and editing of accounts with locale.
- **New `locale_changeset/2`:** For self-service locale updates in account settings. Casts and validates `:locale` only.

### Identity context functions

- **`change_account_locale/2`:** Returns a locale changeset for form rendering.
- **`update_account_locale/2`:** Persists the locale change. Follows the same pattern as `update_account_email/3` and `update_account_password/3`.

### Where locale is set

- **Account creation** (admin `new.ex`): locale select field, defaults to `"en-US"`
- **Account settings** (`settings.ex`): new Language section to change preference
- **Admin account edit** (`edit.ex`): locale select alongside name, email, role
- **Registration** (`registration.ex`): only wrap existing strings in `gettext()` — skip adding locale select since the route is disabled

## 3. Text Extraction & Translation

### Scope

Wrap every user-facing hardcoded string in `gettext()` / `ngettext()` / `pgettext()` calls across the entire app:

- All LiveView modules in `lib/web/live/` (flash messages, assigns, error strings)
- All `.heex` templates (labels, headings, buttons, placeholders, tooltips)
- `lib/web/components/layouts.ex` (nav, header, footer, flash messages, theme toggle)
- `lib/web/components/core_components.ex` (generic labels like "close", pagination)
- `lib/ancestry/identity/account_notifier.ex` (email subjects and bodies)
- Error/success messages in context modules that surface to users

### Not translated

- Schema field names, database values, log messages
- Developer-facing error messages
- Module/function names, route paths

### Translation file structure

```
priv/gettext/
  default.pot
  errors.pot
  en-US/LC_MESSAGES/default.po
  en-US/LC_MESSAGES/errors.po
  es-UY/LC_MESSAGES/default.po
  es-UY/LC_MESSAGES/errors.po
```

### Process

1. Wrap all strings in `gettext()` calls
2. Run `mix gettext.extract` to generate `.pot` templates
3. Run `mix gettext.merge priv/gettext` to create locale `.po` files
4. English `.po` files: original English text as `msgstr`
5. Spanish `.po` files: neutral Latin American Spanish translations

### Spanish translation guidelines

- No voseo — standard "tú" conjugation
- Neutral vocabulary understood across Latin America
- Informal but respectful tone matching the English UI

## 4. LiveView & Plug Integration

### Browser pipeline (`router.ex`)

Add `Web.Locale` plug after auth plugs — ensures locale is set for every request.

### Locale change in settings

1. Save locale to account in DB via `Identity.update_account_locale/2`
2. Call `Gettext.put_locale/1` in the LiveView process
3. Page re-renders in new language immediately

**Note:** LiveView processes cannot update the Plug session directly (`put_session` is not available). The DB is the source of truth for logged-in users. On the next full page load, the `Web.Locale` plug reads the account's persisted locale from the DB and sets the session. No forced redirect is needed — the LiveView re-renders immediately via `Gettext.put_locale/1`, and the session catches up on the next HTTP request.

### Email notifications

- `AccountNotifier` reads recipient account's `locale` field
- Wraps email body in `Gettext.with_locale(account.locale, fn -> ... end)`
- Falls back to `"en-US"` if `account.locale` is nil (e.g., when account struct comes from `apply_action!` on a changeset that didn't include locale)

## 5. UI for Language Selection

### Account settings (`settings.ex`)

- New "Language" section alongside Email and Password
- Select dropdown: "English" / "Español" (each in its own language)
- Follows existing pattern: separate form with `locale_changeset`, validate event, submit event
- On change: updates account via `Identity.update_account_locale/2`, calls `Gettext.put_locale/1`, re-renders

### Admin account creation (`new.ex`)

- Locale select field added to form, defaults to `"en-US"` (uses `admin_changeset`)

### Admin account edit (`edit.ex`)

- Locale select alongside name, email, role (uses `admin_changeset`)

### Language labels

- Always displayed in their own language: "English", "Español"
- User can always find their language regardless of current UI locale

## 6. Testing

### Migration

- Verify existing accounts get `locale: "en-US"` after migration

### Unit tests

- `locale_changeset` validates inclusion in `~w(en-US es-UY)`
- `admin_changeset` casts and validates locale
- `Identity.update_account_locale/2` persists locale

### E2E tests (`test/user_flows/`)

- Changing locale in account settings saves and re-renders in new language
- Admin creating an account with locale persists it
- Admin editing an account's locale persists it
- Logged-out user gets locale from `Accept-Language` header
- Fallback to `"en-US"` when no locale detected

### Plug/hook tests

- `Web.Locale` plug priority: account → session → Accept-Language → default
- `Web.SetLocale` on_mount hook sets locale correctly for LiveViews
- `Web.SetLocale` handles nil `current_scope.account` without crashing (login page)
- `renew_session/2` preserves locale across login
