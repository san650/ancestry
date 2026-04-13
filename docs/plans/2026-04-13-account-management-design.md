# Account Management: Create, Edit, Deactivate & Role-Based Authorization

**Date:** 2026-04-13
**Status:** Draft

## Overview

Add admin-only account management (create, list, show, edit, deactivate/reactivate) with global roles (viewer/editor/admin), account-organization associations, and the Permit authorization framework as the foundation for future permission gating.

## Requirements

1. New admin-only pages: account list, create, show, edit
2. Account fields: email, password, name (optional), avatar/photo (optional), role (viewer/editor/admin, default: editor)
3. Accounts created as validated (confirmed_at set)
4. Many-to-many account-organization association; optional org assignment during creation, editable later
5. Admins access all organizations; non-admins only those they're associated with
6. Soft-delete via deactivation (deactivated_at + deactivated_by); grayed out in list
7. Reactivation by admins
8. Accounts cannot deactivate themselves
9. Deactivated accounts are logged out immediately and cannot log in
10. Permit library for authorization (admin-only page gating); no existing routes gated yet
11. Accounts cannot deactivate the last remaining active admin
12. Accounts cannot change their own role
13. Organization picker filters list for non-admins (only show associated orgs)
14. Organization creation auto-links the creator via `account_organizations`
15. Deactivation/reactivation requires a confirmation modal

## Data Model

### Account Schema Changes

Add to `accounts` table:

| Column | Type | Default | Notes |
|--------|------|---------|-------|
| `name` | `:string` | `nil` | Optional display name |
| `role` | `Ecto.Enum` | `:editor` | Values: `[:viewer, :editor, :admin]` |
| `deactivated_at` | `:utc_datetime` | `nil` | `nil` = active |
| `deactivated_by` | `references(:accounts, on_delete: :nilify_all)` | `nil` | Which admin deactivated |
| `avatar` | `:string` | `nil` | Waffle upload field |
| `avatar_status` | `:string` | `nil` | `"pending"` / `"processed"` / `"failed"` |

The `role` field uses `Ecto.Enum` with `values: [:viewer, :editor, :admin]`. This ensures atoms in the Elixir layer (matching Permit's pattern-match style) and strings in the database. The `deactivated_by` FK uses `on_delete: :nilify_all` — the deactivation fact matters more than who did it if the admin account is ever removed.

**Deactivated accounts retain their email uniqueness.** A deactivated account still occupies its email address — no other account can register with it. This is intentional; reactivation restores the account with its original email.

**Migration for existing accounts:** All existing accounts set to `role: "admin"` (stored as string in DB, cast to atom by Ecto.Enum).

### New Table: `account_organizations`

| Column | Type | Notes |
|--------|------|-------|
| `account_id` | `references(:accounts, on_delete: :delete_all)` | |
| `organization_id` | `references(:organizations, on_delete: :delete_all)` | |
| `inserted_at` | `:utc_datetime` | |
| `updated_at` | `:utc_datetime` | |

Unique index on `{account_id, organization_id}`.

### New Schema: `Ancestry.Organizations.AccountOrganization`

Join schema for the many-to-many relationship. Lives under `Organizations` because it governs organization membership/access, and the `Organizations` context owns the "which orgs can this account see?" query.

### Association Updates

- `Account` gains `has_many :account_organizations, Ancestry.Organizations.AccountOrganization` and `many_to_many :organizations, through: [:account_organizations, :organization]`
- `Organization` gains `has_many :account_organizations` and `many_to_many :accounts`

### New Changeset: `Account.admin_changeset/3`

The existing `email_changeset/3` and `password_changeset/3` don't handle `name`, `role`, or `confirmed_at`. A new `admin_changeset/3` is needed for admin-driven account creation and editing:

- Casts: `[:email, :name, :role, :password]`
- Validates: email format + uniqueness, password length (12-72), role inclusion in Ecto.Enum values
- Sets `confirmed_at` to `DateTime.utc_now()` on creation
- Hashes password via Bcrypt (reuses existing hashing logic)
- **Does NOT reuse `validate_email_changed/1`** from the existing `email_changeset` — that guard rejects changesets where the email hasn't changed, which would block account creation
- **Password handling on edit:** if the `password` param is absent or empty string, skip all password validation and hashing entirely. This is a separate code path from creation where password is required.

## Authorization (Permit)

### Dependencies

Add to `mix.exs`:

```elixir
{:permit, "~> 0.3.3"},
{:permit_phoenix, "~> 0.4.0"}
```

No `permit_ecto` — we don't need automatic record scoping. Records are loaded manually in LiveViews as in the rest of the app.

### Module Structure

**`Ancestry.Actions`** — `use Permit.Phoenix.Actions, router: Web.Router`. Auto-discovers all live_actions from the router with default CanCanCan-style grouping (`:index` → `:read`, `:new` → `:create`, `:show` → `:read`, `:edit` → `:update`).

**`Ancestry.Permissions`** — pattern matches on Scope:

```elixir
def can(%Scope{account: %{role: :admin}}) do
  permit()
  |> all(Ancestry.Identity.Account)
end

def can(%Scope{account: %{role: _}}) do
  permit()  # no account management permissions for non-admins
end

def can(_), do: permit()
```

The `role` field is `Ecto.Enum`, so it arrives as an atom (`:admin`, `:editor`, `:viewer`) — pattern matching works directly.

Only account management is gated for now. Future work extends this to families, galleries, etc.

**`Ancestry.Authorization`** — `use Permit, permissions_module: Ancestry.Permissions`

### LiveView Integration

- `Permit.Phoenix.LiveView.AuthorizeHook` added to the admin live_session's `on_mount` list
- Each account management LiveView uses `use Permit.Phoenix.LiveView, authorization_module: Ancestry.Authorization, resource_module: Ancestry.Identity.Account`
- `handle_unauthorized/2` redirects to `/org` (organization picker) with flash error — admin routes have no org context. Each admin LiveView defines this callback identically; extract to a shared macro if repetitive.

## Routes

New admin live_session in `router.ex`, outside the `/org/:org_id/` scope:

```elixir
live_session :admin,
  on_mount:
    @sandbox_hooks ++
    [
      {Web.AccountAuth, :require_authenticated},
      Permit.Phoenix.LiveView.AuthorizeHook
    ] do
  live "/admin/accounts", AccountManagementLive.Index, :index
  live "/accounts/new", AccountManagementLive.New, :new
  live "/accounts/:id", AccountManagementLive.Show, :show
  live "/accounts/:id/edit", AccountManagementLive.Edit, :edit
end
```

Note: `@sandbox_hooks` is prepended (consistent with all other live_sessions) so E2E tests with PhoenixTest.Playwright and SQL sandbox work correctly.

## Navigation

Add an "Accounts" link in both the desktop header and the mobile nav drawer, visible only when `current_scope.account.role == :admin`. Per learning `layout-attr-passthrough`, ensure the `current_scope` attr is passed from every `Layouts.app` call site (it already is for existing pages).

## LiveView Pages

### Account List (`AccountManagementLive.Index`)

- Global list of all accounts in the system, sorted by email ascending
- Table columns: name, email, organizations (badges/comma-separated), status (active/deactivated)
- Deactivated accounts shown grayed out
- Links to show/edit per row
- Link to create new account
- No pagination for now (acceptable for small user base; add if list grows)

### Create Account (`AccountManagementLive.New`)

- Form fields: name, email, password, password confirmation, role (select: viewer/editor/admin), avatar upload (optional), organizations (multi-select, optional)
- Uses `Account.admin_changeset/3` — account created with `confirmed_at` set to current time (validated)
- Account creation uses **Ecto.Multi**: insert account, then insert `account_organizations` records for selected orgs (per CLAUDE.md multi-table insert pattern)
- Avatar upload follows existing pattern: `allow_upload` → `consume_uploaded_entries` → `Storage.store_original` → Oban job
- Redirects to account list on success

### Show Account (`AccountManagementLive.Show`)

- Displays account details: name, email, role, avatar, organizations, status, deactivated_by (if applicable)
- Deactivate/Reactivate button (hidden when viewing own account), with confirmation modal before action
- Link to edit

### Edit Account (`AccountManagementLive.Edit`)

- Same form fields as create (pre-filled), password fields optional (only set if changing)
- Role select disabled/hidden when editing own account (prevents self-role-change)
- Deactivate/Reactivate button (hidden when viewing own account), with confirmation modal before action
- Avatar upload/replace
- Organization assignment changes
- Redirects to show page on success

## Deactivation Flow

### Deactivate (Ecto.Multi transaction)

1. Verify target is not the current account → `{:error, :cannot_deactivate_self}`
2. Verify target is not the last active admin → count active admins with a row-locking query inside Multi; return `{:error, :last_admin}` if count would drop to zero
3. **Fetch all `account_tokens`** for the target account (needed for step 6)
4. Set `deactivated_at` to `DateTime.utc_now()`
5. Set `deactivated_by` to current admin's account id
6. Delete all `account_tokens` for the deactivated account
7. On Multi success: pass the pre-fetched token structs (from step 3) to `AccountAuth.disconnect_sessions/1`

Steps 1-6 in Multi; step 7 on success only (per learning `post-commit-side-effect-cleanup`). Tokens must be fetched **before** deletion so `disconnect_sessions/1` has the token values to broadcast. The last-admin check uses a locking query to handle concurrent deactivation requests safely.

**`account_organizations` records are retained** on deactivation — reactivation restores org access without re-assignment.

### Reactivate

1. Set `deactivated_at` to `nil`
2. Set `deactivated_by` to `nil`
3. Account can log in again normally

No `reactivated_by` / `reactivated_at` audit trail — intentionally omitted to keep scope minimal. Can be added later if audit requirements emerge.

### Self-Deactivation Prevention

- LiveView hides deactivate button when `@current_scope.account.id == account.id`
- Context function returns `{:error, :cannot_deactivate_self}` as safety net

### Self-Role-Change Prevention

- Edit page disables the role select when editing own account
- Context function returns `{:error, :cannot_change_own_role}` if attempting to change own role (any direction, not just demotion)
- Also enforced by the last-admin check: changing the last admin's role to non-admin is blocked by the same count query

### Admin Password Changes

When an admin changes another account's password via the edit page:
- No `current_password` required (admin doesn't know target's password)
- All sessions for the target account are terminated (same as self-change flow) — ensures compromised credentials are fully invalidated
- Uses the existing `AccountAuth.disconnect_sessions/1` broadcast (same token-fetch-before-delete pattern as deactivation)

### Avatar Retention on Deactivation

Avatar files are **not** cleaned up on deactivation. They remain in S3/local storage so reactivation restores the account with its avatar intact.

### Login Guards

All login paths check `deactivated_at`:

- `Identity.get_account_by_email_and_password/2` — return nil if deactivated (don't reveal account exists)
- `Identity.get_account_by_session_token/1` — return nil if deactivated (covers remember-me)
- `Identity.get_account_by_magic_link_token/1` — return nil if deactivated (prevents deactivated user from reaching confirmation page via unexpired magic link)
- `Identity.login_account_by_magic_link/1` — return nil if deactivated
- `Identity.deliver_login_instructions/2` — silently no-op if account is deactivated (don't send "log in" emails to deactivated accounts; prevents information leak)

## EnsureOrganization Update

The current hook calls `get_organization!/1` which raises on missing org. This must be restructured from a raising pattern to a `{:halt, socket}` pattern to support the authorization redirect.

After the refactor:

1. Load org with a non-raising query; if not found → redirect to `/org` with flash "Organization doesn't exist"
2. If `account.role == :admin` → allow (admins access all organizations)
3. Otherwise, check `account_organizations` for a matching `{account_id, organization_id}` record
4. If no match → redirect to `/org` with flash "Organization doesn't exist"

Same error message for "not found" and "not authorized" — avoids leaking org existence.

**Risk:** This hook is used by every org-scoped route. All existing org routes must be tested after the change to ensure no regressions.

## Organization Picker Update

`OrganizationLive.Index` currently calls `Organizations.list_organizations()` which returns all orgs unconditionally.

Update: add `Organizations.list_organizations_for_account/1` (accepts `%Account{}`, not `%Scope{}`):
- If `account.role == :admin` → return all organizations
- Otherwise → return only organizations linked via `account_organizations`

The `/org` route's LiveView uses this function instead of `list_organizations/0`.

## Organization Creation Update

When a non-admin creates an organization (via the existing create org modal), an `account_organizations` record must be automatically created linking the creator to the new org. Without this, the creator would immediately lose access to the org they just created. This uses Ecto.Multi: insert organization + insert account_organization in one transaction.

## Avatar Processing

### Uploader: `Ancestry.Uploaders.AccountAvatar`

- Versions: `:original`, `:thumbnail` (150x150 crop)
- Storage: Waffle S3 in prod, local in dev
- Path: `uploads/accounts/{account_id}/avatar/`

### Oban Worker: `Ancestry.Workers.ProcessAccountAvatarJob`

- Queue: `:photos` (same as existing photo jobs)
- Fetches original via `Storage.fetch_original/1`
- Runs Waffle/ImageMagick transforms
- Broadcasts `{:avatar_processed, account}` or `{:avatar_failed, account}` over PubSub topic `"account:{id}"`
- Cleans up temp files, deletes original from S3

### Upload Flow in LiveViews

- `allow_upload :avatar, accept: ~w(.jpg .jpeg .png .webp), max_entries: 1, max_file_size: 10_000_000`
- `consume_uploaded_entries` → `Storage.store_original/2` → insert Oban job
- Show/Edit LiveViews subscribe to `"account:{id}"` for real-time avatar status

### Account Schema

- `avatar` field managed by `Ancestry.Uploaders.AccountAvatar` via `use Waffle.Ecto.Schema`
- `avatar_status` (:string, default nil): `"pending"` → `"processed"` / `"failed"`

## Seeding

- Default seed account created as `role: :admin`
- Seed creates `account_organizations` record linking seed account to default organization
- Migration sets all existing accounts to `role: "admin"`

## Applicable Learnings

| Learning | How Applied |
|----------|-------------|
| `layout-attr-passthrough` | Any new layout attrs for admin nav must be passed from every call site |
| `router-on-mount-hooks` | Admin live_session uses router-level on_mount, not per-LiveView |
| `template-struct-field-blind-spot` | Verify avatar field name matches Waffle uploader before template use |
| `post-commit-side-effect-cleanup` | Deactivation: DB changes in Multi, socket disconnect on success only |
| `update-dependent-assigns` | After deactivate/reactivate events, update all derived assigns |
| `use-descriptive-fk-names` | `deactivated_by` column instead of generic `account_id` |
| `audit-generated-auth-defaults` | Login guard changes are deliberate and documented |
| `assign-async-mount` | Consider assign_async for account list with org preloading if heavy |
| `clean-test-output` | E2E tests for avatar processing need actual files present |

## Testing

Per project conventions, all new user flows require E2E tests in `test/user_flows/`.

**Test factory updates required:** The `account_factory` in `test/support/factory.ex` must be updated to include `role: :admin` (default, since existing tests assume full access). A new `account_organization_factory` is needed. Without these, the EnsureOrganization refactor will break every existing E2E test that visits org-scoped routes.

**Test cases:**

- **Create account:** admin creates account with email, password, name, role, orgs → appears in list
- **Edit account:** admin edits name, role, org assignments → changes reflected
- **Edit own account:** role select is disabled, deactivate button hidden
- **Admin password change:** admin changes another account's password → target sessions terminated
- **Deactivate account:** admin deactivates another account → grayed in list, cannot log in
- **Deactivation confirmation:** clicking deactivate shows confirmation modal before executing
- **Reactivate account:** admin reactivates account → active in list, can log in again
- **Self-deactivation prevention:** deactivate button hidden for own account
- **Last-admin protection:** deactivating the last active admin returns error
- **Self-role-change prevention:** cannot change own role
- **Non-admin access denied:** viewer/editor redirected when accessing `/admin/accounts`
- **Org access gating:** non-admin without org association gets "Organization doesn't exist"
- **Org picker filtering:** non-admin sees only associated orgs at `/org`
- **Org creation auto-link:** non-admin creates org → automatically linked via account_organizations
- **Avatar upload:** admin uploads avatar → processed via Oban → displayed on show/edit
- **EnsureOrganization regression:** all existing org-scoped routes still work after hook refactor
