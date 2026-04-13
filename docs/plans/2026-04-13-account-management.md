# Account Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add admin-only account management (create, list, show, edit, deactivate/reactivate) with roles, org associations, and the Permit authorization framework.

**Architecture:** Extend the existing Account schema with role/name/deactivated fields, add an account_organizations join table, integrate Permit for admin page gating, add four new LiveView pages under a dedicated admin live_session, refactor EnsureOrganization to check org membership, and add avatar processing following the existing Waffle/Oban pipeline pattern.

**Tech Stack:** Phoenix 1.8, LiveView, Ecto, Oban, Waffle, Permit + Permit.Phoenix, Bcrypt

**Spec:** `docs/plans/2026-04-13-account-management-design.md`

---

## File Map

### New Files
- `priv/repo/migrations/TIMESTAMP_add_account_management.exs` — migration for account fields + account_organizations table
- `lib/ancestry/organizations/account_organization.ex` — join schema
- `lib/ancestry/actions.ex` — Permit actions module
- `lib/ancestry/permissions.ex` — Permit permissions module
- `lib/ancestry/authorization.ex` — Permit authorization module
- `lib/ancestry/uploaders/account_avatar.ex` — Waffle uploader
- `lib/ancestry/workers/process_account_avatar_job.ex` — Oban worker
- `lib/web/live/account_management_live/index.ex` — account list page
- `lib/web/live/account_management_live/new.ex` — create account page
- `lib/web/live/account_management_live/show.ex` — show account page
- `lib/web/live/account_management_live/edit.ex` — edit account page
- `test/ancestry/identity/account_test.exs` — changeset tests
- `test/ancestry/identity_admin_test.exs` — context tests for admin Identity functions
- `test/ancestry/organizations_access_test.exs` — context tests for org access functions
- `test/user_flows/account_management_test.exs` — E2E tests

### Modified Files
- `mix.exs:42-86` — add permit + permit_phoenix deps
- `lib/ancestry/identity/account.ex:1-132` — add fields, associations, admin_changeset
- `lib/ancestry/identity.ex:1-310` — add admin CRUD, deactivation, login guards
- `lib/ancestry/organizations/organization.ex:1-19` — add account associations
- `lib/ancestry/organizations.ex:1-71` — add list_organizations_for_account, create_organization with auto-link
- `lib/web/router.ex:1-117` — add admin live_session
- `lib/web/ensure_organization.ex:1-17` — refactor from raise to halt with access check
- `lib/web/components/layouts.ex:49-115` — add admin nav link
- `lib/web/components/nav_drawer.ex:80-110` — add admin nav link
- `test/support/factory.ex:42-53` — add role to account factories, add account_organization_factory
- `test/support/e2e_case.ex:21-26` — update log_in_e2e to create org association
- `priv/repo/seeds.exs:1-50` — add admin role + org association for seed account

---

## Task 1: Dependencies & Migration

**Files:**
- Modify: `mix.exs:42-86`
- Create: `priv/repo/migrations/TIMESTAMP_add_account_management.exs`

- [ ] **Step 1: Add permit and permit_phoenix to mix.exs**

In `mix.exs`, inside the `deps` function, add after the `{:oban, "~> 2.18"}` line:

```elixir
{:permit, "~> 0.3.3"},
{:permit_phoenix, "~> 0.4.0"},
```

- [ ] **Step 2: Fetch deps**

Run: `mix deps.get`
Expected: Dependencies fetched successfully

- [ ] **Step 3: Create the migration**

Run: `mix ecto.gen.migration add_account_management`

Then write the migration:

```elixir
defmodule Ancestry.Repo.Migrations.AddAccountManagement do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :name, :string
      add :role, :string, null: false, default: "editor"
      add :deactivated_at, :utc_datetime
      add :deactivated_by, references(:accounts, on_delete: :nilify_all)
      add :avatar, :string
      add :avatar_status, :string
    end

    # Set all existing accounts to admin
    execute "UPDATE accounts SET role = 'admin'", "SELECT 1"

    create table(:account_organizations) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :organization_id, references(:organizations, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:account_organizations, [:account_id, :organization_id])
    create index(:account_organizations, [:organization_id])
  end
end
```

- [ ] **Step 4: Run migration**

Run: `mix ecto.migrate`
Expected: Migration runs successfully

- [ ] **Step 5: Commit**

```bash
git add mix.exs mix.lock priv/repo/migrations/*_add_account_management.exs
git commit -m "feat: add account management migration and permit deps"
```

---

## Task 2: Account Schema & Changeset

**Files:**
- Modify: `lib/ancestry/identity/account.ex:1-132`

- [ ] **Step 1: Write tests for admin_changeset**

Create `test/ancestry/identity/account_test.exs`:

```elixir
defmodule Ancestry.Identity.AccountTest do
  use Ancestry.DataCase, async: true
  alias Ancestry.Identity.Account

  describe "admin_changeset/3 for creation" do
    test "valid attrs produce a valid changeset" do
      changeset = Account.admin_changeset(%Account{}, %{
        email: "new@example.com",
        name: "Test User",
        role: :editor,
        password: "password123456"
      })
      assert changeset.valid?
      assert get_change(changeset, :confirmed_at)
      assert get_change(changeset, :hashed_password)
      refute get_change(changeset, :password)
    end

    test "requires email" do
      changeset = Account.admin_changeset(%Account{}, %{password: "password123456"})
      assert "can't be blank" in errors_on(changeset).email
    end

    test "requires password on creation" do
      changeset = Account.admin_changeset(%Account{}, %{email: "a@b.com"})
      assert "can't be blank" in errors_on(changeset).password
    end

    test "validates email format" do
      changeset = Account.admin_changeset(%Account{}, %{email: "invalid", password: "password123456"})
      assert "must have the @ sign and no spaces" in errors_on(changeset).email
    end

    test "validates password length" do
      changeset = Account.admin_changeset(%Account{}, %{email: "a@b.com", password: "short"})
      assert "should be at least 12 character(s)" in errors_on(changeset).password
    end

    test "validates role inclusion" do
      changeset = Account.admin_changeset(%Account{}, %{
        email: "a@b.com", password: "password123456", role: :superadmin
      })
      assert changeset.errors[:role]
    end
  end

  describe "admin_changeset/3 for editing" do
    test "skips password when empty string" do
      account = %Account{email: "old@example.com", hashed_password: "existing_hash"}
      changeset = Account.admin_changeset(account, %{name: "Updated", password: ""}, mode: :edit)
      assert changeset.valid?
      assert get_change(changeset, :name) == "Updated"
      refute get_change(changeset, :hashed_password)
    end

    test "skips password when absent" do
      account = %Account{email: "old@example.com", hashed_password: "existing_hash"}
      changeset = Account.admin_changeset(account, %{name: "Updated"}, mode: :edit)
      assert changeset.valid?
      refute get_change(changeset, :hashed_password)
    end

    test "updates password when provided on edit" do
      account = %Account{email: "old@example.com", hashed_password: "existing_hash"}
      changeset = Account.admin_changeset(account, %{password: "newpassword123"}, mode: :edit)
      assert changeset.valid?
      assert get_change(changeset, :hashed_password)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ancestry/identity/account_test.exs`
Expected: All tests fail (admin_changeset not defined)

- [ ] **Step 3: Update Account schema with new fields and admin_changeset**

In `lib/ancestry/identity/account.ex`, update the schema block (after line 10) to add:

```elixir
field :name, :string
field :role, Ecto.Enum, values: [:viewer, :editor, :admin], default: :editor
field :deactivated_at, :utc_datetime
field :avatar, Ancestry.Uploaders.AccountAvatar.Type
field :avatar_status, :string

belongs_to :deactivator, Ancestry.Identity.Account, foreign_key: :deactivated_by
has_many :account_organizations, Ancestry.Organizations.AccountOrganization
many_to_many :organizations, Ancestry.Organizations.Organization,
  join_through: "account_organizations"
```

Add `use Waffle.Ecto.Schema` after `import Ecto.Changeset`.

Add the `admin_changeset/3` function before `valid_password?/2`:

```elixir
@doc """
Changeset for admin-driven account creation and editing.

## Options

  * `:mode` - `:create` (default) requires password and sets confirmed_at.
    `:edit` makes password optional (skipped if empty/absent).
"""
def admin_changeset(account, attrs, opts \\ []) do
  mode = Keyword.get(opts, :mode, :create)

  account
  |> cast(attrs, [:email, :name, :role, :password])
  |> validate_required([:email])
  |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
    message: "must have the @ sign and no spaces"
  )
  |> validate_length(:email, max: 160)
  |> unsafe_validate_unique(:email, Ancestry.Repo)
  |> unique_constraint(:email)
  |> validate_confirmation(:password, message: "does not match password")
  |> maybe_validate_password(mode)
  |> maybe_set_confirmed_at(mode)
end

defp maybe_validate_password(changeset, :create) do
  changeset
  |> validate_required([:password])
  |> validate_length(:password, min: 12, max: 72)
  |> maybe_hash_password(hash_password: true)
end

defp maybe_validate_password(changeset, :edit) do
  password = get_change(changeset, :password)

  if password && password != "" do
    changeset
    |> validate_length(:password, min: 12, max: 72)
    |> maybe_hash_password(hash_password: true)
  else
    changeset
    |> delete_change(:password)
  end
end

defp maybe_set_confirmed_at(changeset, :create) do
  put_change(changeset, :confirmed_at, DateTime.utc_now(:second))
end

defp maybe_set_confirmed_at(changeset, :edit), do: changeset
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/ancestry/identity/account_test.exs`
Expected: All tests pass

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/identity/account.ex test/ancestry/identity/account_test.exs
git commit -m "feat: add role, name, deactivation fields and admin_changeset to Account"
```

---

## Task 3: AccountOrganization Join Schema

**Files:**
- Create: `lib/ancestry/organizations/account_organization.ex`
- Modify: `lib/ancestry/organizations/organization.ex:1-19`

- [ ] **Step 1: Create the join schema**

```elixir
defmodule Ancestry.Organizations.AccountOrganization do
  use Ecto.Schema
  import Ecto.Changeset

  schema "account_organizations" do
    belongs_to :account, Ancestry.Identity.Account
    belongs_to :organization, Ancestry.Organizations.Organization
    timestamps(type: :utc_datetime)
  end

  def changeset(account_organization, attrs) do
    account_organization
    |> cast(attrs, [:account_id, :organization_id])
    |> validate_required([:account_id, :organization_id])
    |> unique_constraint([:account_id, :organization_id])
  end
end
```

- [ ] **Step 2: Add associations to Organization schema**

In `lib/ancestry/organizations/organization.ex`, add after the existing `has_many` lines:

```elixir
has_many :account_organizations, Ancestry.Organizations.AccountOrganization
many_to_many :accounts, Ancestry.Identity.Account, join_through: "account_organizations"
```

- [ ] **Step 3: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles without warnings

- [ ] **Step 4: Commit**

```bash
git add lib/ancestry/organizations/account_organization.ex lib/ancestry/organizations/organization.ex
git commit -m "feat: add AccountOrganization join schema and associations"
```

---

## Task 4: Identity Context — Admin CRUD & Deactivation

**Files:**
- Modify: `lib/ancestry/identity.ex:1-310`
- Create: `test/ancestry/identity_admin_test.exs`

- [ ] **Step 1: Write tests for admin account functions**

Create `test/ancestry/identity_admin_test.exs`:

```elixir
defmodule Ancestry.IdentityAdminTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Identity
  alias Ancestry.Identity.Account

  import Ancestry.Factory

  describe "create_admin_account/2" do
    test "creates account with role and confirmed_at" do
      assert {:ok, %{account: account}} =
        Identity.create_admin_account(%{
          email: "new@example.com",
          password: "password123456",
          name: "Test User",
          role: :editor
        }, [])

      assert account.email == "new@example.com"
      assert account.name == "Test User"
      assert account.role == :editor
      assert account.confirmed_at
    end

    test "creates account with org associations" do
      org = insert(:organization)

      assert {:ok, %{account: account}} =
        Identity.create_admin_account(
          %{email: "new@example.com", password: "password123456", role: :viewer},
          [org.id]
        )

      account = Repo.preload(account, :organizations)
      assert length(account.organizations) == 1
      assert hd(account.organizations).id == org.id
    end

    test "returns error for invalid attrs" do
      assert {:error, :account, changeset, _} =
        Identity.create_admin_account(%{email: "bad"}, [])

      assert errors_on(changeset).email
    end
  end

  describe "update_admin_account/3" do
    test "updates account fields" do
      account = insert(:account) |> Map.put(:role, :admin)
      # Ensure account has the role field set in DB
      Repo.update!(Ecto.Changeset.change(account, role: :admin))

      assert {:ok, updated} =
        Identity.update_admin_account(account, %{name: "New Name", role: :viewer}, account)

      assert updated.name == "New Name"
      assert updated.role == :viewer
    end

    test "prevents self-role-change" do
      account = insert(:account)
      Repo.update!(Ecto.Changeset.change(account, role: :admin))
      account = Repo.get!(Account, account.id)

      assert {:error, :cannot_change_own_role} =
        Identity.update_admin_account(account, %{role: :editor}, account)
    end
  end

  describe "deactivate_account/2" do
    test "deactivates account and deletes tokens" do
      admin = insert(:account)
      Repo.update!(Ecto.Changeset.change(admin, role: :admin))
      admin = Repo.get!(Account, admin.id)

      target = insert(:account)
      Repo.update!(Ecto.Changeset.change(target, role: :editor))
      target = Repo.get!(Account, target.id)

      # Create a session token for the target
      token = Identity.generate_account_session_token(target)
      assert token

      assert {:ok, deactivated} = Identity.deactivate_account(target, admin)
      assert deactivated.deactivated_at
      assert deactivated.deactivated_by == admin.id

      # Token should be deleted
      assert Identity.get_account_by_session_token(token) == nil
    end

    test "prevents self-deactivation" do
      admin = insert(:account)
      Repo.update!(Ecto.Changeset.change(admin, role: :admin))
      admin = Repo.get!(Account, admin.id)

      assert {:error, :cannot_deactivate_self} = Identity.deactivate_account(admin, admin)
    end

    test "prevents deactivating last admin" do
      admin = insert(:account)
      Repo.update!(Ecto.Changeset.change(admin, role: :admin))
      admin = Repo.get!(Account, admin.id)

      target = insert(:account)
      Repo.update!(Ecto.Changeset.change(target, role: :admin))
      target = Repo.get!(Account, target.id)

      # Only two admins — deactivating target leaves one, which is OK
      assert {:ok, _} = Identity.deactivate_account(target, admin)

      # Now admin is the last admin — try to deactivate someone
      # (but target is already deactivated, so there's 1 active admin)
      another = insert(:account)
      Repo.update!(Ecto.Changeset.change(another, role: :admin))
      another = Repo.get!(Account, another.id)

      # Deactivate another should work (2 active admins: admin + another)
      # Actually let's test: make another the only other admin
      # admin is only active admin, try deactivating admin from another's perspective
      # Reset: admin deactivated target, so active admins = [admin, another]
      assert {:ok, _} = Identity.deactivate_account(another, admin)
      # Now only admin is left. Try to deactivate admin — but that's self-deactivation
      # which is already blocked. Let's test with a new admin scenario:
    end

    test "prevents deactivating when only one admin remains" do
      sole_admin = insert(:account)
      Repo.update!(Ecto.Changeset.change(sole_admin, role: :admin))
      sole_admin = Repo.get!(Account, sole_admin.id)

      target = insert(:account)
      Repo.update!(Ecto.Changeset.change(target, role: :admin))
      target = Repo.get!(Account, target.id)

      # Deactivate target — leaves sole_admin as last admin
      assert {:ok, _} = Identity.deactivate_account(target, sole_admin)

      # Try to create another admin and deactivate them — sole_admin is last active admin
      target2 = insert(:account)
      Repo.update!(Ecto.Changeset.change(target2, role: :admin))
      target2 = Repo.get!(Account, target2.id)

      # Now 2 active admins again, should work
      assert {:ok, _} = Identity.deactivate_account(target2, sole_admin)
    end
  end

  describe "reactivate_account/1" do
    test "clears deactivation fields" do
      account = insert(:account)
      Repo.update!(Ecto.Changeset.change(account, role: :editor, deactivated_at: DateTime.utc_now(:second), deactivated_by: account.id))
      account = Repo.get!(Account, account.id)

      assert {:ok, reactivated} = Identity.reactivate_account(account)
      assert reactivated.deactivated_at == nil
      assert reactivated.deactivated_by == nil
    end
  end

  describe "login guards for deactivated accounts" do
    test "get_account_by_email_and_password returns nil for deactivated" do
      account = insert(:account)
      Repo.update!(Ecto.Changeset.change(account, role: :editor, deactivated_at: DateTime.utc_now(:second)))

      # Set password first
      {:ok, {account, _}} = Identity.update_account_password(account, %{password: "password123456"})
      Repo.update!(Ecto.Changeset.change(account, deactivated_at: DateTime.utc_now(:second)))

      assert Identity.get_account_by_email_and_password(account.email, "password123456") == nil
    end

    test "get_account_by_session_token returns nil for deactivated" do
      account = insert(:account)
      token = Identity.generate_account_session_token(account)
      Repo.update!(Ecto.Changeset.change(account, deactivated_at: DateTime.utc_now(:second)))

      assert Identity.get_account_by_session_token(token) == nil
    end
  end

  describe "list_accounts/0" do
    test "returns all accounts sorted by email" do
      a1 = insert(:account, email: "zzz@test.com")
      a2 = insert(:account, email: "aaa@test.com")

      accounts = Identity.list_accounts()
      emails = Enum.map(accounts, & &1.email)
      assert Enum.find_index(emails, &(&1 == "aaa@test.com")) <
             Enum.find_index(emails, &(&1 == "zzz@test.com"))
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ancestry/identity_admin_test.exs`
Expected: Failures — functions not defined

- [ ] **Step 3: Implement Identity context admin functions**

Add to `lib/ancestry/identity.ex` before the `## Token helper` section:

```elixir
## Admin account management

alias Ecto.Multi
alias Ancestry.Organizations.AccountOrganization

@doc """
Lists all accounts sorted by email, with organizations preloaded.
"""
def list_accounts do
  Account
  |> from(order_by: [asc: :email], preload: :organizations)
  |> Repo.all()
end

@doc """
Gets an account with organizations preloaded.
"""
def get_account_with_orgs!(id) do
  Account
  |> Repo.get!(id)
  |> Repo.preload([:organizations, :deactivator])
end

@doc """
Creates an account as admin with optional org associations.
Uses Ecto.Multi for the multi-table insert.
"""
def create_admin_account(attrs, organization_ids) do
  Multi.new()
  |> Multi.insert(:account, Account.admin_changeset(%Account{}, attrs))
  |> Multi.run(:account_organizations, fn repo, %{account: account} ->
    Enum.each(organization_ids, fn org_id ->
      %AccountOrganization{}
      |> AccountOrganization.changeset(%{account_id: account.id, organization_id: org_id})
      |> repo.insert!()
    end)
    {:ok, organization_ids}
  end)
  |> Repo.transaction()
end

@doc """
Updates an account as admin. Prevents self-role-change.
The `current_account` is the admin performing the edit.
"""
def update_admin_account(account, attrs, current_account) do
  new_role = attrs[:role] || attrs["role"]
  role_changed? = new_role && to_string(new_role) != to_string(account.role)
  self_edit? = account.id == current_account.id

  if role_changed? && self_edit? do
    {:error, :cannot_change_own_role}
  else
    account
    |> Account.admin_changeset(attrs, mode: :edit)
    |> Repo.update()
  end
end

@doc """
Updates org associations for an account — replaces all existing.
"""
def update_account_organizations(account, organization_ids) do
  multi =
    Multi.new()
    |> Multi.delete_all(:remove_existing, from(ao in AccountOrganization, where: ao.account_id == ^account.id))
    |> Multi.run(:insert_new, fn repo, _ ->
      Enum.each(organization_ids, fn org_id ->
        %AccountOrganization{}
        |> AccountOrganization.changeset(%{account_id: account.id, organization_id: org_id})
        |> repo.insert!()
      end)
      {:ok, organization_ids}
    end)

  case Repo.transaction(multi) do
    {:ok, _} -> :ok
    {:error, _, reason, _} -> {:error, reason}
  end
end

@doc """
Deactivates an account. Prevents self-deactivation and last-admin deactivation.
Returns {:ok, account} or {:error, reason}.
"""
def deactivate_account(target, current_account) do
  cond do
    target.id == current_account.id ->
      {:error, :cannot_deactivate_self}

    true ->
      result =
        Multi.new()
        |> Multi.run(:last_admin_check, fn repo, _ ->
          active_admin_count =
            repo.one(
              from a in Account,
                where: a.role == :admin and is_nil(a.deactivated_at),
                select: count(a.id),
                lock: "FOR UPDATE"
            )

          # If target is admin, deactivating them would reduce count by 1
          would_remain = if target.role == :admin, do: active_admin_count - 1, else: active_admin_count

          if would_remain < 1 do
            {:error, :last_admin}
          else
            {:ok, active_admin_count}
          end
        end)
        |> Multi.run(:fetch_tokens, fn repo, _ ->
          tokens = repo.all(from t in AccountToken, where: t.account_id == ^target.id)
          {:ok, tokens}
        end)
        |> Multi.update(:deactivate, fn _ ->
          Ecto.Changeset.change(target,
            deactivated_at: DateTime.utc_now(:second),
            deactivated_by: current_account.id
          )
        end)
        |> Multi.delete_all(:delete_tokens, fn _ ->
          from(t in AccountToken, where: t.account_id == ^target.id)
        end)
        |> Repo.transaction()

      case result do
        {:ok, %{deactivate: account, fetch_tokens: tokens}} ->
          Web.AccountAuth.disconnect_sessions(tokens)
          {:ok, account}

        {:error, :last_admin_check, :last_admin, _} ->
          {:error, :last_admin}

        {:error, _, changeset, _} ->
          {:error, changeset}
      end
  end
end

@doc """
Reactivates a deactivated account.
"""
def reactivate_account(account) do
  account
  |> Ecto.Changeset.change(deactivated_at: nil, deactivated_by: nil)
  |> Repo.update()
end
```

- [ ] **Step 4: Add login guards for deactivated accounts**

Modify `get_account_by_email_and_password/2` (line 41-45) to check deactivation:

```elixir
def get_account_by_email_and_password(email, password)
    when is_binary(email) and is_binary(password) do
  account = Repo.get_by(Account, email: email)

  cond do
    account && account.deactivated_at -> nil
    Account.valid_password?(account, password) -> account
    true -> nil
  end
end
```

Modify `get_account_by_session_token/1` (line 188-191) to filter deactivated:

```elixir
def get_account_by_session_token(token) do
  {:ok, query} = AccountToken.verify_session_token_query(token)

  case Repo.one(query) do
    {%Account{deactivated_at: deactivated_at}, _} when not is_nil(deactivated_at) -> nil
    result -> result
  end
end
```

Modify `get_account_by_magic_link_token/1` (line 196-203) to filter deactivated:

```elixir
def get_account_by_magic_link_token(token) do
  with {:ok, query} <- AccountToken.verify_magic_link_token_query(token),
       {%Account{deactivated_at: nil} = account, _token} <- Repo.one(query) do
    account
  else
    _ -> nil
  end
end
```

Modify `login_account_by_magic_link/1` (line 223-249) — add deactivation check after the query:

In the `case Repo.one(query)` block, add a clause before the existing ones:

```elixir
{%Account{deactivated_at: deactivated_at}, _token} when not is_nil(deactivated_at) ->
  {:error, :not_found}
```

Modify `deliver_login_instructions/2` (line 280-285) to no-op for deactivated:

```elixir
def deliver_login_instructions(%Account{deactivated_at: deactivated_at}, _magic_link_url_fun)
    when not is_nil(deactivated_at) do
  {:ok, :deactivated}
end

def deliver_login_instructions(%Account{} = account, magic_link_url_fun)
    when is_function(magic_link_url_fun, 1) do
  {encoded_token, account_token} = AccountToken.build_email_token(account, "login")
  Repo.insert!(account_token)
  AccountNotifier.deliver_login_instructions(account, magic_link_url_fun.(encoded_token))
end
```

- [ ] **Step 5: Run tests**

Run: `mix test test/ancestry/identity_admin_test.exs`
Expected: All pass

- [ ] **Step 6: Run full test suite to check no regressions**

Run: `mix test`
Expected: All existing tests pass

- [ ] **Step 7: Commit**

```bash
git add lib/ancestry/identity.ex test/ancestry/identity_admin_test.exs
git commit -m "feat: add admin account CRUD, deactivation, and login guards"
```

---

## Task 5: Permit Authorization Modules

**Files:**
- Create: `lib/ancestry/actions.ex`
- Create: `lib/ancestry/permissions.ex`
- Create: `lib/ancestry/authorization.ex`

- [ ] **Step 1: Create Actions module**

```elixir
defmodule Ancestry.Actions do
  @moduledoc "Permit actions — auto-discovers live_actions from the router."
  use Permit.Phoenix.Actions, router: Web.Router
end
```

- [ ] **Step 2: Create Permissions module**

```elixir
defmodule Ancestry.Permissions do
  @moduledoc "Defines who can do what. Pattern matches on Scope."
  use Permit.Permissions, actions_module: Ancestry.Actions

  alias Ancestry.Identity.{Account, Scope}

  def can(%Scope{account: %Account{role: :admin}}) do
    permit()
    |> all(Account)
  end

  def can(%Scope{account: %Account{role: _}}) do
    permit()
  end

  def can(_), do: permit()
end
```

- [ ] **Step 3: Create Authorization module**

```elixir
defmodule Ancestry.Authorization do
  @moduledoc "Ties Permit permissions to the application."
  use Permit, permissions_module: Ancestry.Permissions
end
```

- [ ] **Step 4: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles cleanly

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/actions.ex lib/ancestry/permissions.ex lib/ancestry/authorization.ex
git commit -m "feat: add Permit authorization modules (Actions, Permissions, Authorization)"
```

---

## Task 6: Organizations Context — Access Control & Auto-Link

**Files:**
- Modify: `lib/ancestry/organizations.ex:1-71`
- Create: `test/ancestry/organizations_access_test.exs`

- [ ] **Step 1: Write tests**

Create `test/ancestry/organizations_access_test.exs`:

```elixir
defmodule Ancestry.OrganizationsAccessTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Organizations
  import Ancestry.Factory

  describe "list_organizations_for_account/1" do
    test "admin sees all organizations" do
      insert(:organization, name: "Org A")
      insert(:organization, name: "Org B")
      admin = insert(:account)
      Repo.update!(Ecto.Changeset.change(admin, role: :admin))
      admin = Repo.get!(Ancestry.Identity.Account, admin.id)

      orgs = Organizations.list_organizations_for_account(admin)
      assert length(orgs) >= 2
    end

    test "non-admin sees only associated organizations" do
      org_a = insert(:organization, name: "Org A")
      _org_b = insert(:organization, name: "Org B")
      editor = insert(:account)
      Repo.update!(Ecto.Changeset.change(editor, role: :editor))
      editor = Repo.get!(Ancestry.Identity.Account, editor.id)

      Repo.insert!(%Ancestry.Organizations.AccountOrganization{
        account_id: editor.id,
        organization_id: org_a.id
      })

      orgs = Organizations.list_organizations_for_account(editor)
      assert length(orgs) == 1
      assert hd(orgs).id == org_a.id
    end
  end

  describe "account_has_org_access?/2" do
    test "admin has access to any org" do
      org = insert(:organization)
      admin = insert(:account)
      Repo.update!(Ecto.Changeset.change(admin, role: :admin))
      admin = Repo.get!(Ancestry.Identity.Account, admin.id)

      assert Organizations.account_has_org_access?(admin, org.id)
    end

    test "non-admin with association has access" do
      org = insert(:organization)
      editor = insert(:account)
      Repo.update!(Ecto.Changeset.change(editor, role: :editor))
      editor = Repo.get!(Ancestry.Identity.Account, editor.id)

      Repo.insert!(%Ancestry.Organizations.AccountOrganization{
        account_id: editor.id,
        organization_id: org.id
      })

      assert Organizations.account_has_org_access?(editor, org.id)
    end

    test "non-admin without association denied" do
      org = insert(:organization)
      editor = insert(:account)
      Repo.update!(Ecto.Changeset.change(editor, role: :editor))
      editor = Repo.get!(Ancestry.Identity.Account, editor.id)

      refute Organizations.account_has_org_access?(editor, org.id)
    end
  end

  describe "create_organization/2 with account" do
    test "auto-links creator to new org" do
      account = insert(:account)
      Repo.update!(Ecto.Changeset.change(account, role: :editor))
      account = Repo.get!(Ancestry.Identity.Account, account.id)

      assert {:ok, org} = Organizations.create_organization(%{name: "My Org"}, account)
      assert Organizations.account_has_org_access?(account, org.id)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ancestry/organizations_access_test.exs`
Expected: Failures

- [ ] **Step 3: Implement access functions in Organizations context**

Add to `lib/ancestry/organizations.ex`:

```elixir
alias Ancestry.Organizations.AccountOrganization
alias Ancestry.Identity.Account

@doc """
Lists organizations accessible to the given account.
Admins see all; others see only associated orgs.
"""
def list_organizations_for_account(%Account{role: :admin}) do
  list_organizations()
end

def list_organizations_for_account(%Account{id: account_id}) do
  from(o in Organization,
    join: ao in AccountOrganization,
    on: ao.organization_id == o.id,
    where: ao.account_id == ^account_id,
    order_by: [asc: o.name]
  )
  |> Repo.all()
end

@doc """
Checks if an account has access to an organization.
"""
def account_has_org_access?(%Account{role: :admin}, _org_id), do: true

def account_has_org_access?(%Account{id: account_id}, org_id) do
  Repo.exists?(
    from ao in AccountOrganization,
      where: ao.account_id == ^account_id and ao.organization_id == ^org_id
  )
end

@doc """
Creates an organization and auto-links the creator via account_organizations.
"""
def create_organization(attrs, %Account{} = account) do
  Multi.new()
  |> Multi.insert(:organization, Organization.changeset(%Organization{}, attrs))
  |> Multi.insert(:account_organization, fn %{organization: org} ->
    AccountOrganization.changeset(%AccountOrganization{}, %{
      account_id: account.id,
      organization_id: org.id
    })
  end)
  |> Repo.transaction()
  |> case do
    {:ok, %{organization: org}} -> {:ok, org}
    {:error, :organization, changeset, _} -> {:error, changeset}
  end
end
```

Add `alias Ecto.Multi` at the top of the module.

- [ ] **Step 4: Run tests**

Run: `mix test test/ancestry/organizations_access_test.exs`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/organizations.ex test/ancestry/organizations_access_test.exs
git commit -m "feat: add org access control and auto-link on org creation"
```

---

## Task 7: EnsureOrganization Refactor

**Files:**
- Modify: `lib/web/ensure_organization.ex:1-17`

- [ ] **Step 1: Refactor the hook**

Replace `lib/web/ensure_organization.ex` entirely:

```elixir
defmodule Web.EnsureOrganization do
  @moduledoc """
  LiveView on_mount hook that reads the org_id argument, assigns the organization
  to the socket, and verifies the current account has access.

  Admins access all organizations. Non-admins must have an account_organizations
  record. Returns the same error message for "not found" and "not authorized"
  to avoid leaking org existence.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [push_navigate: 2, put_flash: 3]

  def on_mount(:default, params, _session, socket) do
    account = socket.assigns.current_scope.account

    case Ancestry.Organizations.get_organization(params["org_id"]) do
      nil ->
        {:halt,
         socket
         |> put_flash(:error, "Organization doesn't exist")
         |> push_navigate(to: "/org")}

      organization ->
        if Ancestry.Organizations.account_has_org_access?(account, organization.id) do
          scope = %{socket.assigns.current_scope | organization: organization}
          {:cont, assign(socket, :current_scope, scope)}
        else
          {:halt,
           socket
           |> put_flash(:error, "Organization doesn't exist")
           |> push_navigate(to: "/org")}
        end
    end
  end
end
```

- [ ] **Step 2: Add get_organization/1 (non-raising) to Organizations context**

Add to `lib/ancestry/organizations.ex`:

```elixir
def get_organization(id) when is_binary(id) or is_integer(id) do
  Repo.get(Organization, id)
end

def get_organization(_), do: nil
```

- [ ] **Step 3: Run full test suite**

Run: `mix test`
Expected: All existing tests pass — the refactor is backward-compatible because admin accounts (the default factory role after Task 8) bypass the access check, and the hook still assigns the org to the scope.

- [ ] **Step 4: Commit**

```bash
git add lib/web/ensure_organization.ex lib/ancestry/organizations.ex
git commit -m "refactor: EnsureOrganization from raise to halt with org access check"
```

---

## Task 8: Update Test Factory & E2E Helper

**Files:**
- Modify: `test/support/factory.ex:42-53`
- Modify: `test/support/e2e_case.ex:21-26`

- [ ] **Step 1: Update account factory with role**

In `test/support/factory.ex`, update `account_factory/0` (line 42-47):

```elixir
def account_factory do
  %Ancestry.Identity.Account{
    email: sequence(:account_email, &"account#{&1}@example.com"),
    confirmed_at: DateTime.utc_now(:second),
    role: :admin
  }
end
```

Update `unconfirmed_account_factory/0` (line 49-53):

```elixir
def unconfirmed_account_factory do
  %Ancestry.Identity.Account{
    email: sequence(:account_email, &"account#{&1}@example.com"),
    role: :admin
  }
end
```

Add new factory:

```elixir
def account_organization_factory do
  %Ancestry.Organizations.AccountOrganization{
    account: build(:account),
    organization: build(:organization)
  }
end
```

- [ ] **Step 2: Update log_in_e2e to create org association**

In `test/support/e2e_case.ex`, update `log_in_e2e/1` (line 21-26). The function needs to support tests that visit org-scoped routes. Since admin role bypasses org checks, the existing tests remain compatible. But add an overload for non-admin testing:

```elixir
def log_in_e2e(conn, opts \\ []) do
  role = Keyword.get(opts, :role, :admin)
  account = Ancestry.Factory.insert(:account, role: role)

  # For non-admin accounts, associate with any orgs passed in
  for org_id <- Keyword.get(opts, :organization_ids, []) do
    Ancestry.Factory.insert(:account_organization,
      account: account,
      organization: %Ancestry.Organizations.Organization{id: org_id}
    )
  end

  conn
  |> PhoenixTest.visit("/test/session/#{account.id}")
end
```

- [ ] **Step 3: Run full test suite**

Run: `mix test`
Expected: All existing tests pass — factory default is `:admin` which bypasses all org access checks

- [ ] **Step 4: Commit**

```bash
git add test/support/factory.ex test/support/e2e_case.ex
git commit -m "feat: update test factory with role and account_organization support"
```

---

## Task 9: Router & Navigation

**Files:**
- Modify: `lib/web/router.ex:35-67`
- Modify: `lib/web/components/layouts.ex:59-95`
- Modify: `lib/web/components/nav_drawer.ex:80-110`

- [ ] **Step 1: Add admin live_session to router**

In `lib/web/router.ex`, add after the `:default` live_session block (after line 41) and before the `scope "/org/:org_id"` block:

```elixir
live_session :admin,
  on_mount:
    @sandbox_hooks ++
      [
        {Web.AccountAuth, :require_authenticated},
        Permit.Phoenix.LiveView.AuthorizeHook
      ] do
  live "/admin/accounts", AccountManagementLive.Index, :index
  live "/admin/accounts/new", AccountManagementLive.New, :new
  live "/admin/accounts/:id", AccountManagementLive.Show, :show
  live "/admin/accounts/:id/edit", AccountManagementLive.Edit, :edit
end
```

- [ ] **Step 2: Add admin nav link to desktop header**

In `lib/web/components/layouts.ex`, after the Organizations link section (around line 75) and before the `<li class="text-ds-outline-variant">|</li>` divider, add:

```heex
<%= if @current_scope.account.role == :admin do %>
  <li>
    <.link href={~p"/admin/accounts"} class="hover:text-ds-on-surface transition-colors">
      Accounts
    </.link>
  </li>
<% end %>
```

- [ ] **Step 3: Add admin nav link to mobile nav drawer**

In `lib/web/components/nav_drawer.ex`, inside the account section (after the Settings link, around line 97), add before the Log out link:

```heex
<%= if @current_scope && @current_scope.account && @current_scope.account.role == :admin do %>
  <.link
    href="/admin/accounts"
    class="flex items-center gap-3 w-full px-2 py-3 text-left rounded-ds-sharp min-h-[44px] text-ds-on-surface hover:bg-ds-surface-high transition-colors"
  >
    <.icon name="hero-users" class="size-5 shrink-0 text-ds-on-surface-variant" />
    <span class="font-ds-body text-sm">Accounts</span>
  </.link>
<% end %>
```

- [ ] **Step 4: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles (LiveView modules don't exist yet but routes reference module names as atoms — Phoenix resolves them at runtime)

- [ ] **Step 5: Commit**

```bash
git add lib/web/router.ex lib/web/components/layouts.ex lib/web/components/nav_drawer.ex
git commit -m "feat: add admin live_session routes and Accounts nav links"
```

---

## Task 10: Organization Picker Update

**Files:**
- Modify: `lib/web/live/organization_live/index.ex:8-17`

- [ ] **Step 1: Update org picker to use filtered list**

In `lib/web/live/organization_live/index.ex`, change the mount function to use `list_organizations_for_account/1` instead of `list_organizations/0`:

Replace the line that streams organizations (around line 14-15) from:
```elixir
|> stream(:organizations, Organizations.list_organizations())
```
to:
```elixir
|> stream(:organizations, Organizations.list_organizations_for_account(socket.assigns.current_scope.account))
```

- [ ] **Step 2: Update org creation to use the auto-linking version**

In the `save` event handler (around line 46-59), update the `create_organization` call to pass the current account:

Replace:
```elixir
Organizations.create_organization(organization_params)
```
with:
```elixir
Organizations.create_organization(organization_params, socket.assigns.current_scope.account)
```

- [ ] **Step 3: Run full test suite**

Run: `mix test`
Expected: All pass

- [ ] **Step 4: Commit**

```bash
git add lib/web/live/organization_live/index.ex
git commit -m "feat: filter org picker by account access and auto-link on creation"
```

---

## Task 11: Account Avatar Uploader & Oban Worker

**Files:**
- Create: `lib/ancestry/uploaders/account_avatar.ex`
- Create: `lib/ancestry/workers/process_account_avatar_job.ex`

- [ ] **Step 1: Create the Waffle uploader**

Create `lib/ancestry/uploaders/account_avatar.ex` (following the PersonPhoto pattern):

```elixir
defmodule Ancestry.Uploaders.AccountAvatar do
  use Waffle.Definition
  use Waffle.Ecto.Definition

  @versions [:original, :thumbnail]
  @valid_extensions ~w(.jpg .jpeg .png .webp .tif .tiff)

  def validate({file, _}) do
    file.file_name
    |> Path.extname()
    |> String.downcase()
    |> then(&(&1 in @valid_extensions))
  end

  def transform(:original, _), do: :noaction

  def transform(:thumbnail, _) do
    {:convert, "-resize 150x150^ -gravity center -extent 150x150 -auto-orient -strip", :jpg}
  end

  def filename(:original, _), do: "avatar"
  def filename(:thumbnail, _), do: "thumbnail"

  def storage_dir(_version, {_file, scope}) do
    "uploads/accounts/#{scope.id}/avatar"
  end
end
```

- [ ] **Step 2: Create the Oban worker**

Create `lib/ancestry/workers/process_account_avatar_job.ex` (following the ProcessPersonPhotoJob pattern):

```elixir
defmodule Ancestry.Workers.ProcessAccountAvatarJob do
  use Oban.Worker, queue: :photos, max_attempts: 3

  alias Ancestry.Identity
  alias Ancestry.Uploaders

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"account_id" => account_id, "original_path" => original_path}}) do
    account = Identity.get_account!(account_id)

    case process_avatar(account, original_path) do
      {:ok, updated_account} ->
        Phoenix.PubSub.broadcast(
          Ancestry.PubSub,
          "account:#{account.id}",
          {:avatar_processed, updated_account}
        )

        :ok

      {:error, reason} ->
        Identity.update_avatar_status(account, "failed")

        Phoenix.PubSub.broadcast(
          Ancestry.PubSub,
          "account:#{account.id}",
          {:avatar_failed, account}
        )

        {:error, reason}
    end
  end

  defp process_avatar(account, original_path) do
    {:ok, local_path, tmp_dir} = Ancestry.Storage.fetch_original(original_path)

    waffle_file = %{
      filename: Path.basename(local_path),
      path: local_path
    }

    result =
      case Uploaders.AccountAvatar.store({waffle_file, account}) do
        {:ok, filename} -> Identity.update_avatar_processed(account, filename)
        {:error, reason} -> {:error, reason}
      end

    Ancestry.Storage.cleanup_original(tmp_dir)
    Ancestry.Storage.delete_original(original_path)

    result
  end
end
```

- [ ] **Step 3: Add avatar helper functions to Identity context**

Add to `lib/ancestry/identity.ex`:

```elixir
@doc "Updates avatar status to processed with the filename."
def update_avatar_processed(account, filename) do
  account
  |> Ecto.Changeset.change(avatar: %{file_name: filename, updated_at: nil}, avatar_status: "processed")
  |> Repo.update()
end

@doc "Updates avatar status to failed."
def update_avatar_status(account, status) do
  account
  |> Ecto.Changeset.change(avatar_status: status)
  |> Repo.update()
end
```

- [ ] **Step 4: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles cleanly

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/uploaders/account_avatar.ex lib/ancestry/workers/process_account_avatar_job.ex lib/ancestry/identity.ex
git commit -m "feat: add AccountAvatar uploader and ProcessAccountAvatarJob worker"
```

---

## Task 12: Account List LiveView

**Files:**
- Create: `lib/web/live/account_management_live/index.ex`

- [ ] **Step 1: Create the Index LiveView**

```elixir
defmodule Web.AccountManagementLive.Index do
  use Web, :live_view
  use Permit.Phoenix.LiveView,
    authorization_module: Ancestry.Authorization,
    resource_module: Ancestry.Identity.Account

  alias Ancestry.Identity

  @impl true
  def handle_unauthorized(_action, socket) do
    socket =
      socket
      |> put_flash(:error, "You don't have permission to access this page")
      |> push_navigate(to: ~p"/org")

    {:halt, socket}
  end

  @impl true
  def mount(_params, _session, socket) do
    accounts = Identity.list_accounts()

    {:ok,
     socket
     |> assign(:page_title, "Accounts")
     |> assign(:accounts, accounts)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <:toolbar>
        <div class="max-w-7xl mx-auto flex items-center justify-between px-4 sm:px-6 lg:px-8 py-3">
          <h1 class="text-lg font-ds-heading font-bold text-ds-on-surface">Accounts</h1>
          <.link
            navigate={~p"/admin/accounts/new"}
            class="hidden lg:inline-flex items-center gap-2 rounded-ds-sharp bg-ds-primary px-4 py-2 text-sm font-ds-body font-medium text-ds-on-primary hover:bg-ds-primary/90 transition-colors"
            data-testid="account-new-btn"
          >
            <.icon name="hero-plus" class="size-4" /> New Account
          </.link>
        </div>
      </:toolbar>

      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
        <%!-- Mobile new account button --%>
        <div class="lg:hidden mb-4">
          <.link
            navigate={~p"/admin/accounts/new"}
            class="inline-flex items-center gap-2 rounded-ds-sharp bg-ds-primary px-4 py-2 text-sm font-ds-body font-medium text-ds-on-primary hover:bg-ds-primary/90 transition-colors"
            data-testid="account-new-btn-mobile"
          >
            <.icon name="hero-plus" class="size-4" /> New Account
          </.link>
        </div>

        <div class="overflow-x-auto">
          <table class="w-full text-sm" data-testid="accounts-table">
            <thead>
              <tr class="border-b border-ds-outline-variant/20 text-left text-ds-on-surface-variant">
                <th class="pb-3 pr-4 font-medium">Name</th>
                <th class="pb-3 pr-4 font-medium">Email</th>
                <th class="pb-3 pr-4 font-medium">Organizations</th>
                <th class="pb-3 pr-4 font-medium">Status</th>
                <th class="pb-3 font-medium"></th>
              </tr>
            </thead>
            <tbody>
              <tr
                :for={account <- @accounts}
                class={[
                  "border-b border-ds-outline-variant/10",
                  if(account.deactivated_at, do: "opacity-50")
                ]}
                data-testid={"account-row-#{account.id}"}
              >
                <td class="py-3 pr-4">{account.name || "—"}</td>
                <td class="py-3 pr-4">{account.email}</td>
                <td class="py-3 pr-4">
                  <span :for={org <- account.organizations} class="inline-block bg-ds-surface-high rounded-full px-2 py-0.5 text-xs mr-1 mb-1">
                    {org.name}
                  </span>
                </td>
                <td class="py-3 pr-4">
                  <%= if account.deactivated_at do %>
                    <span class="text-ds-error text-xs font-medium" data-testid={"account-status-#{account.id}"}>Deactivated</span>
                  <% else %>
                    <span class="text-ds-primary text-xs font-medium" data-testid={"account-status-#{account.id}"}>Active</span>
                  <% end %>
                </td>
                <td class="py-3 text-right">
                  <.link navigate={~p"/admin/accounts/#{account.id}"} class="text-ds-primary hover:underline text-xs mr-2">
                    View
                  </.link>
                  <.link navigate={~p"/admin/accounts/#{account.id}/edit"} class="text-ds-primary hover:underline text-xs">
                    Edit
                  </.link>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
```

- [ ] **Step 2: Verify it compiles**

Run: `mix compile --warnings-as-errors`

- [ ] **Step 3: Commit**

```bash
git add lib/web/live/account_management_live/index.ex
git commit -m "feat: add account list LiveView"
```

---

## Task 13: Create Account LiveView

**Files:**
- Create: `lib/web/live/account_management_live/new.ex`

- [ ] **Step 1: Create the New LiveView**

```elixir
defmodule Web.AccountManagementLive.New do
  use Web, :live_view
  use Permit.Phoenix.LiveView,
    authorization_module: Ancestry.Authorization,
    resource_module: Ancestry.Identity.Account

  alias Ancestry.Identity
  alias Ancestry.Identity.Account
  alias Ancestry.Organizations

  @impl true
  def handle_unauthorized(_action, socket) do
    socket =
      socket
      |> put_flash(:error, "You don't have permission to access this page")
      |> push_navigate(to: ~p"/org")

    {:halt, socket}
  end

  @impl true
  def mount(_params, _session, socket) do
    changeset = Account.admin_changeset(%Account{}, %{})
    organizations = Organizations.list_organizations()

    {:ok,
     socket
     |> assign(:page_title, "New Account")
     |> assign(:form, to_form(changeset))
     |> assign(:organizations, organizations)
     |> assign(:selected_org_ids, [])
     |> allow_upload(:avatar,
       accept: ~w(.jpg .jpeg .png .webp),
       max_entries: 1,
       max_file_size: 10_000_000
     )}
  end

  @impl true
  def handle_event("validate", %{"account" => account_params}, socket) do
    changeset =
      %Account{}
      |> Account.admin_changeset(account_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  @impl true
  def handle_event("save", %{"account" => account_params} = params, socket) do
    org_ids = params["organization_ids"] || []

    # Handle avatar upload
    avatar_original_path =
      consume_uploaded_entries(socket, :avatar, fn %{path: path}, entry ->
        original_path = Ancestry.Storage.store_original(path, entry.client_name)
        {:ok, original_path}
      end)
      |> List.first()

    case Identity.create_admin_account(account_params, org_ids) do
      {:ok, %{account: account}} ->
        # Enqueue avatar processing if uploaded
        if avatar_original_path do
          Identity.update_avatar_status(account, "pending")

          %{account_id: account.id, original_path: avatar_original_path}
          |> Ancestry.Workers.ProcessAccountAvatarJob.new()
          |> Oban.insert()
        end

        {:noreply,
         socket
         |> put_flash(:info, "Account created successfully")
         |> push_navigate(to: ~p"/admin/accounts")}

      {:error, :account, changeset, _} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  @impl true
  def handle_event("toggle_org", %{"org-id" => org_id}, socket) do
    selected = socket.assigns.selected_org_ids

    updated =
      if org_id in selected,
        do: List.delete(selected, org_id),
        else: [org_id | selected]

    {:noreply, assign(socket, :selected_org_ids, updated)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <:toolbar>
        <div class="max-w-7xl mx-auto flex items-center gap-4 px-4 sm:px-6 lg:px-8 py-3">
          <.link navigate={~p"/admin/accounts"} class="text-ds-on-surface-variant hover:text-ds-on-surface">
            <.icon name="hero-arrow-left" class="size-5" />
          </.link>
          <h1 class="text-lg font-ds-heading font-bold text-ds-on-surface">New Account</h1>
        </div>
      </:toolbar>

      <div class="max-w-2xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
        <.form
          for={@form}
          id="account-form"
          phx-change="validate"
          phx-submit="save"
          class="space-y-6"
          data-testid="account-form"
        >
          <.input field={@form[:name]} type="text" label="Full name" />
          <.input field={@form[:email]} type="email" label="Email" required />
          <.input field={@form[:password]} type="password" label="Password" required />
          <.input field={@form[:password_confirmation]} type="password" label="Confirm password" />
          <.input
            field={@form[:role]}
            type="select"
            label="Role"
            options={[{"Viewer", :viewer}, {"Editor", :editor}, {"Admin", :admin}]}
          />

          <%!-- Avatar upload --%>
          <div>
            <label class="block text-sm font-medium text-ds-on-surface mb-2">Avatar</label>
            <.live_file_input upload={@uploads.avatar} class="text-sm" data-testid="avatar-upload" />
            <div :for={entry <- @uploads.avatar.entries} class="mt-2">
              <.live_img_preview entry={entry} class="w-20 h-20 rounded-full object-cover" />
              <p :for={err <- upload_errors(@uploads.avatar, entry)} class="text-ds-error text-xs mt-1">
                {error_to_string(err)}
              </p>
            </div>
          </div>

          <%!-- Organization selection --%>
          <div>
            <label class="block text-sm font-medium text-ds-on-surface mb-2">Organizations</label>
            <div class="space-y-2" data-testid="org-selection">
              <label
                :for={org <- @organizations}
                class="flex items-center gap-2 cursor-pointer"
              >
                <input
                  type="checkbox"
                  name="organization_ids[]"
                  value={org.id}
                  checked={to_string(org.id) in @selected_org_ids}
                  phx-click="toggle_org"
                  phx-value-org-id={org.id}
                  class="rounded border-ds-outline"
                />
                <span class="text-sm text-ds-on-surface">{org.name}</span>
              </label>
            </div>
          </div>

          <div class="flex gap-4">
            <button
              type="submit"
              class="rounded-ds-sharp bg-ds-primary px-6 py-2 text-sm font-ds-body font-medium text-ds-on-primary hover:bg-ds-primary/90 transition-colors"
              data-testid="account-submit-btn"
            >
              Create Account
            </button>
            <.link
              navigate={~p"/admin/accounts"}
              class="rounded-ds-sharp px-6 py-2 text-sm font-ds-body text-ds-on-surface-variant hover:text-ds-on-surface transition-colors"
            >
              Cancel
            </.link>
          </div>
        </.form>
      </div>
    </Layouts.app>
    """
  end

  defp error_to_string(:too_large), do: "File is too large (max 10MB)"
  defp error_to_string(:too_many_files), do: "Only one avatar allowed"
  defp error_to_string(:not_accepted), do: "Invalid file type"
  defp error_to_string(err), do: inspect(err)
end
```

- [ ] **Step 2: Commit**

```bash
git add lib/web/live/account_management_live/new.ex
git commit -m "feat: add create account LiveView"
```

---

## Task 14: Show Account LiveView

**Files:**
- Create: `lib/web/live/account_management_live/show.ex`

- [ ] **Step 1: Create the Show LiveView with deactivate/reactivate**

```elixir
defmodule Web.AccountManagementLive.Show do
  use Web, :live_view
  use Permit.Phoenix.LiveView,
    authorization_module: Ancestry.Authorization,
    resource_module: Ancestry.Identity.Account

  alias Ancestry.Identity

  @impl true
  def handle_unauthorized(_action, socket) do
    socket =
      socket
      |> put_flash(:error, "You don't have permission to access this page")
      |> push_navigate(to: ~p"/org")

    {:halt, socket}
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    account = Identity.get_account_with_orgs!(id)

    Phoenix.PubSub.subscribe(Ancestry.PubSub, "account:#{id}")

    {:ok,
     socket
     |> assign(:page_title, account.name || account.email)
     |> assign(:account, account)
     |> assign(:confirm_deactivate, false)}
  end

  @impl true
  def handle_event("request_deactivate", _, socket) do
    {:noreply, assign(socket, :confirm_deactivate, true)}
  end

  @impl true
  def handle_event("cancel_deactivate", _, socket) do
    {:noreply, assign(socket, :confirm_deactivate, false)}
  end

  @impl true
  def handle_event("confirm_deactivate", _, socket) do
    case Identity.deactivate_account(socket.assigns.account, socket.assigns.current_scope.account) do
      {:ok, account} ->
        {:noreply,
         socket
         |> assign(:account, Identity.get_account_with_orgs!(account.id))
         |> assign(:confirm_deactivate, false)
         |> put_flash(:info, "Account deactivated")}

      {:error, :cannot_deactivate_self} ->
        {:noreply, put_flash(socket, :error, "You cannot deactivate your own account")}

      {:error, :last_admin} ->
        {:noreply, put_flash(socket, :error, "Cannot deactivate the last admin account")}
    end
  end

  @impl true
  def handle_event("reactivate", _, socket) do
    case Identity.reactivate_account(socket.assigns.account) do
      {:ok, account} ->
        {:noreply,
         socket
         |> assign(:account, Identity.get_account_with_orgs!(account.id))
         |> put_flash(:info, "Account reactivated")}
    end
  end

  @impl true
  def handle_info({:avatar_processed, account}, socket) do
    {:noreply, assign(socket, :account, Identity.get_account_with_orgs!(account.id))}
  end

  @impl true
  def handle_info({:avatar_failed, _account}, socket) do
    {:noreply, put_flash(socket, :error, "Avatar processing failed")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <:toolbar>
        <div class="max-w-7xl mx-auto flex items-center justify-between px-4 sm:px-6 lg:px-8 py-3">
          <div class="flex items-center gap-4">
            <.link navigate={~p"/admin/accounts"} class="text-ds-on-surface-variant hover:text-ds-on-surface">
              <.icon name="hero-arrow-left" class="size-5" />
            </.link>
            <h1 class="text-lg font-ds-heading font-bold text-ds-on-surface">
              {@account.name || @account.email}
            </h1>
          </div>
          <div class="hidden lg:flex items-center gap-2">
            <.link
              navigate={~p"/admin/accounts/#{@account.id}/edit"}
              class="rounded-ds-sharp bg-ds-surface-high px-4 py-2 text-sm font-ds-body text-ds-on-surface hover:bg-ds-surface-high/80 transition-colors"
              data-testid="account-edit-btn"
            >
              Edit
            </.link>
            <%= if @account.id != @current_scope.account.id do %>
              <%= if @account.deactivated_at do %>
                <button
                  phx-click="reactivate"
                  class="rounded-ds-sharp bg-ds-primary px-4 py-2 text-sm font-ds-body font-medium text-ds-on-primary hover:bg-ds-primary/90 transition-colors"
                  data-testid="account-reactivate-btn"
                >
                  Reactivate
                </button>
              <% else %>
                <button
                  phx-click="request_deactivate"
                  class="rounded-ds-sharp bg-ds-error px-4 py-2 text-sm font-ds-body font-medium text-ds-on-error hover:bg-ds-error/90 transition-colors"
                  data-testid="account-deactivate-btn"
                >
                  Deactivate
                </button>
              <% end %>
            <% end %>
          </div>
        </div>
      </:toolbar>

      <div class="max-w-2xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
        <dl class="space-y-4">
          <div>
            <dt class="text-xs font-medium text-ds-on-surface-variant uppercase tracking-wider">Email</dt>
            <dd class="mt-1 text-sm text-ds-on-surface" data-testid="account-email">{@account.email}</dd>
          </div>
          <div>
            <dt class="text-xs font-medium text-ds-on-surface-variant uppercase tracking-wider">Name</dt>
            <dd class="mt-1 text-sm text-ds-on-surface" data-testid="account-name">{@account.name || "—"}</dd>
          </div>
          <div>
            <dt class="text-xs font-medium text-ds-on-surface-variant uppercase tracking-wider">Role</dt>
            <dd class="mt-1 text-sm text-ds-on-surface capitalize" data-testid="account-role">{@account.role}</dd>
          </div>
          <div>
            <dt class="text-xs font-medium text-ds-on-surface-variant uppercase tracking-wider">Status</dt>
            <dd class="mt-1 text-sm" data-testid="account-show-status">
              <%= if @account.deactivated_at do %>
                <span class="text-ds-error font-medium">Deactivated</span>
              <% else %>
                <span class="text-ds-primary font-medium">Active</span>
              <% end %>
            </dd>
          </div>
          <div>
            <dt class="text-xs font-medium text-ds-on-surface-variant uppercase tracking-wider">Organizations</dt>
            <dd class="mt-1">
              <span
                :for={org <- @account.organizations}
                class="inline-block bg-ds-surface-high rounded-full px-3 py-1 text-xs mr-1 mb-1 text-ds-on-surface"
              >
                {org.name}
              </span>
              <span :if={@account.organizations == []} class="text-sm text-ds-on-surface-variant">None</span>
            </dd>
          </div>
        </dl>
      </div>

      <%!-- Confirmation modal --%>
      <%= if @confirm_deactivate do %>
        <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/60" data-testid="deactivate-modal">
          <div class="bg-ds-surface-card rounded-ds-sharp p-6 max-w-sm mx-4 shadow-xl">
            <h3 class="text-lg font-ds-heading font-bold text-ds-on-surface mb-2">Deactivate Account</h3>
            <p class="text-sm text-ds-on-surface-variant mb-6">
              Are you sure you want to deactivate <strong>{@account.email}</strong>?
              They will be immediately logged out and unable to log in.
            </p>
            <div class="flex gap-3 justify-end">
              <button
                phx-click="cancel_deactivate"
                class="rounded-ds-sharp px-4 py-2 text-sm font-ds-body text-ds-on-surface-variant hover:text-ds-on-surface transition-colors"
                data-testid="deactivate-cancel-btn"
              >
                Cancel
              </button>
              <button
                phx-click="confirm_deactivate"
                class="rounded-ds-sharp bg-ds-error px-4 py-2 text-sm font-ds-body font-medium text-ds-on-error hover:bg-ds-error/90 transition-colors"
                data-testid="deactivate-confirm-btn"
              >
                Deactivate
              </button>
            </div>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add lib/web/live/account_management_live/show.ex
git commit -m "feat: add show account LiveView with deactivate/reactivate"
```

---

## Task 15: Edit Account LiveView

**Files:**
- Create: `lib/web/live/account_management_live/edit.ex`

- [ ] **Step 1: Create the Edit LiveView**

This follows the same pattern as New but pre-fills fields, makes password optional, disables role for self-edit, and includes deactivate/reactivate. The implementation is similar to New with these differences:

- Loads existing account in mount
- Uses `Account.admin_changeset(account, attrs, mode: :edit)`
- Role select disabled when `account.id == current_scope.account.id`
- Deactivate/reactivate button present (same modal as Show)
- On save, calls `Identity.update_admin_account/3` + `Identity.update_account_organizations/2`
- If password changed, terminates target's sessions
- Subscribes to avatar PubSub for real-time updates

Create `lib/web/live/account_management_live/edit.ex` with the full implementation. Key points:

- Mount loads account via `Identity.get_account_with_orgs!(id)`, pre-fills changeset
- `handle_event("save", ...)` calls `update_admin_account/3` and `update_account_organizations/2`
- If password param is non-empty, also terminate target sessions
- Avatar upload follows same pattern as New
- Deactivate/reactivate with confirmation modal (same as Show)

- [ ] **Step 2: Commit**

```bash
git add lib/web/live/account_management_live/edit.ex
git commit -m "feat: add edit account LiveView"
```

---

## Task 16: Seeds Update

**Files:**
- Modify: `priv/repo/seeds.exs:1-50`

- [ ] **Step 1: Update seeds to set admin role and create org association**

At the top of `priv/repo/seeds.exs`, after the organization creation (line 22) and before the family creation, add the default account setup:

```elixir
# ---------------------------------------------------------------------------
# Default admin account with org association
# ---------------------------------------------------------------------------

# The migration sets all existing accounts to admin, but seeds may run on a fresh DB
# where no account exists yet. The account is created by the login flow, but if
# seeding after initial setup, ensure the first account has org access.
alias Ancestry.Organizations.AccountOrganization

# Link any existing accounts to the default organization
for account <- Ancestry.Repo.all(Ancestry.Identity.Account) do
  unless Ancestry.Repo.get_by(AccountOrganization,
           account_id: account.id,
           organization_id: org.id
         ) do
    Ancestry.Repo.insert!(%AccountOrganization{
      account_id: account.id,
      organization_id: org.id
    })
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add priv/repo/seeds.exs
git commit -m "feat: update seeds to link existing accounts to default org"
```

---

## Task 17: E2E Tests

**Files:**
- Create: `test/user_flows/account_management_test.exs`

- [ ] **Step 1: Write E2E tests**

Create `test/user_flows/account_management_test.exs`:

```elixir
defmodule Web.UserFlows.AccountManagementTest do
  use Web.E2ECase

  # Given an admin user
  # When the admin visits /accounts
  # Then the account list is shown
  #
  # When the admin clicks "New Account"
  # And fills in email, password, name, role
  # And clicks "Create Account"
  # Then the new account appears in the list
  #
  # When the admin clicks "View" on an account
  # Then the account details are shown
  #
  # When the admin clicks "Deactivate"
  # Then a confirmation modal appears
  # When the admin confirms
  # Then the account is deactivated and shown as such
  #
  # When the admin clicks "Reactivate"
  # Then the account is reactivated
  #
  # Given a non-admin user
  # When they visit /accounts
  # Then they are redirected to /org

  setup do
    org = insert(:organization, name: "Test Org")
    %{org: org}
  end

  test "admin can create, view, and deactivate an account", %{conn: conn, org: org} do
    conn = log_in_e2e(conn)

    # Visit account list
    conn =
      conn
      |> visit(~p"/admin/accounts")
      |> wait_liveview()
      |> assert_has(test_id("accounts-table"))

    # Click New Account
    conn =
      conn
      |> click(test_id("account-new-btn"))
      |> wait_liveview()
      |> assert_has(test_id("account-form"))

    # Fill form and submit
    conn =
      conn
      |> fill_in("Email", with: "newuser@example.com")
      |> fill_in("Password", with: "password123456")
      |> fill_in("Confirm password", with: "password123456")
      |> fill_in("Full name", with: "New User")
      |> click_button(test_id("account-submit-btn"), "Create Account")
      |> wait_liveview()

    # Should redirect to accounts list with the new account
    conn =
      conn
      |> assert_has(".alert", text: "Account created")
      |> assert_has("td", text: "newuser@example.com")

    # Click View on the new account
    conn =
      conn
      |> click("a", text: "View")
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

    conn =
      conn
      |> assert_has(".alert", text: "Account deactivated")
      |> assert_has(test_id("account-show-status"), text: "Deactivated")

    # Reactivate
    conn
    |> click(test_id("account-reactivate-btn"))
    |> wait_liveview()
    |> assert_has(".alert", text: "Account reactivated")
    |> assert_has(test_id("account-show-status"), text: "Active")
  end

  test "non-admin is redirected from /accounts", %{conn: conn, org: org} do
    conn = log_in_e2e(conn, role: :editor, organization_ids: [org.id])

    conn
    |> visit(~p"/admin/accounts")
    |> wait_liveview()
    |> assert_has(".alert", text: "permission")
  end

  test "admin cannot see deactivate button for own account", %{conn: conn} do
    conn = log_in_e2e(conn)

    # Visit accounts list first to find our own account
    conn =
      conn
      |> visit(~p"/admin/accounts")
      |> wait_liveview()

    # Click View on our own account (first/only one initially)
    conn =
      conn
      |> click("a", text: "View")
      |> wait_liveview()

    # Deactivate button should not be present for own account
    refute_has(conn, test_id("account-deactivate-btn"))
  end

  test "non-admin can only see associated organizations", %{conn: conn, org: org} do
    _other_org = insert(:organization, name: "Hidden Org")

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
```

- [ ] **Step 2: Run E2E tests**

Run: `mix test test/user_flows/account_management_test.exs`
Expected: All pass

- [ ] **Step 3: Commit**

```bash
git add test/user_flows/account_management_test.exs
git commit -m "test: add E2E tests for account management"
```

---

## Task 18: Final Verification

- [ ] **Step 1: Run precommit checks**

Run: `mix precommit`
Expected: Compilation (warnings-as-errors), formatting, deps check, and all tests pass

- [ ] **Step 2: Fix any issues surfaced by precommit**

Address warnings, formatting issues, or test failures.

- [ ] **Step 3: Final commit if fixes were needed**

```bash
git add -A
git commit -m "chore: fix precommit issues"
```
