# Centralized Authorization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lay the groundwork for centralized Permit-based authorization: expand permission rules, add a template helper, replace existing scattered role checks, and document the LiveView migration pattern.

**Architecture:** Permissions defined in `Ancestry.Permissions.can/1` by role. A `can?/3` helper wraps Permit's API for template use. LiveView migration is incremental — this plan covers foundation + one example migration.

**Tech Stack:** Permit, Permit.Phoenix, Phoenix LiveView

**Spec:** `docs/plans/2026-04-13-centralized-authorization-design.md`

---

### Task 1: Expand Permission Rules

**Files:**
- Modify: `lib/ancestry/permissions.ex`
- Create: `test/ancestry/permissions_test.exs`

- [ ] **Step 1: Write failing tests for permission rules**

```elixir
defmodule Ancestry.PermissionsTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Authorization
  alias Ancestry.Identity.{Account, Scope}
  alias Ancestry.Families.Family
  alias Ancestry.People.Person
  alias Ancestry.Galleries.{Gallery, Photo}
  alias Ancestry.Organizations.Organization

  defp scope_for(role) do
    %Scope{account: %Account{role: role}}
  end

  describe "admin permissions" do
    test "has full access to all resources" do
      auth = Authorization.can(scope_for(:admin))

      assert Authorization.read?(auth, Account)
      assert Authorization.create?(auth, Account)
      assert Authorization.delete?(auth, Account)

      assert Authorization.read?(auth, Organization)
      assert Authorization.create?(auth, Organization)

      assert Authorization.read?(auth, Family)
      assert Authorization.create?(auth, Family)
      assert Authorization.delete?(auth, Family)

      assert Authorization.read?(auth, Person)
      assert Authorization.create?(auth, Person)

      assert Authorization.read?(auth, Gallery)
      assert Authorization.read?(auth, Photo)
    end
  end

  describe "editor permissions" do
    test "has full access to content resources" do
      auth = Authorization.can(scope_for(:editor))

      assert Authorization.read?(auth, Family)
      assert Authorization.create?(auth, Family)
      assert Authorization.delete?(auth, Family)

      assert Authorization.read?(auth, Person)
      assert Authorization.create?(auth, Person)

      assert Authorization.read?(auth, Gallery)
      assert Authorization.create?(auth, Gallery)

      assert Authorization.read?(auth, Photo)
      assert Authorization.create?(auth, Photo)
    end

    test "can read organizations but not manage them" do
      auth = Authorization.can(scope_for(:editor))

      assert Authorization.read?(auth, Organization)
      refute Authorization.create?(auth, Organization)
      refute Authorization.delete?(auth, Organization)
    end

    test "cannot manage accounts" do
      auth = Authorization.can(scope_for(:editor))

      refute Authorization.read?(auth, Account)
      refute Authorization.create?(auth, Account)
    end
  end

  describe "viewer permissions" do
    test "can read content resources" do
      auth = Authorization.can(scope_for(:viewer))

      assert Authorization.read?(auth, Family)
      assert Authorization.read?(auth, Person)
      assert Authorization.read?(auth, Gallery)
      assert Authorization.read?(auth, Photo)
      assert Authorization.read?(auth, Organization)
    end

    test "cannot create, update, or delete content" do
      auth = Authorization.can(scope_for(:viewer))

      refute Authorization.create?(auth, Family)
      refute Authorization.update?(auth, Family)
      refute Authorization.delete?(auth, Family)

      refute Authorization.create?(auth, Person)
      refute Authorization.create?(auth, Photo)
    end

    test "cannot manage accounts" do
      auth = Authorization.can(scope_for(:viewer))

      refute Authorization.read?(auth, Account)
      refute Authorization.create?(auth, Account)
    end
  end

  describe "unauthenticated" do
    test "has no permissions" do
      auth = Authorization.can(nil)

      refute Authorization.read?(auth, Family)
      refute Authorization.read?(auth, Account)
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ancestry/permissions_test.exs`
Expected: Failures — editor/viewer clauses don't grant permissions on Family, Person, etc.

- [ ] **Step 3: Update permissions module**

Replace `lib/ancestry/permissions.ex` with:

```elixir
defmodule Ancestry.Permissions do
  @moduledoc "Defines who can do what. Pattern matches on Scope."
  use Permit.Permissions, actions_module: Ancestry.Actions

  alias Ancestry.Identity.{Account, Scope}
  alias Ancestry.Families.Family
  alias Ancestry.People.Person
  alias Ancestry.Galleries.{Gallery, Photo}
  alias Ancestry.Organizations.Organization

  def can(%Scope{account: %Account{role: :admin}}) do
    permit()
    |> all(Account)
    |> all(Organization)
    |> all(Family)
    |> all(Person)
    |> all(Gallery)
    |> all(Photo)
  end

  def can(%Scope{account: %Account{role: :editor}}) do
    permit()
    |> all(Family)
    |> all(Person)
    |> all(Gallery)
    |> all(Photo)
    |> read(Organization)
  end

  def can(%Scope{account: %Account{role: :viewer}}) do
    permit()
    |> read(Family)
    |> read(Person)
    |> read(Gallery)
    |> read(Photo)
    |> read(Organization)
  end

  def can(_), do: permit()
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/ancestry/permissions_test.exs`
Expected: All pass

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/permissions.ex test/ancestry/permissions_test.exs
git commit -m "feat: expand Permit permission rules for all resource types"
```

---

### Task 2: Add `can?/3` Template Helper

**Files:**
- Modify: `lib/ancestry/authorization.ex`
- Modify: `lib/web.ex`
- Create: `test/ancestry/authorization_test.exs`

Permit's native API is `can(scope) |> read?(Resource)`. For templates, a `can?/3` wrapper is cleaner.

- [ ] **Step 1: Write failing test for `can?/3`**

```elixir
defmodule Ancestry.AuthorizationTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Authorization
  alias Ancestry.Identity.{Account, Scope}
  alias Ancestry.Families.Family

  defp scope_for(role) do
    %Scope{account: %Account{role: role}}
  end

  describe "can?/3" do
    test "returns true when scope has permission" do
      assert Authorization.can?(scope_for(:admin), :read, Family)
      assert Authorization.can?(scope_for(:editor), :create, Family)
    end

    test "returns false when scope lacks permission" do
      refute Authorization.can?(scope_for(:viewer), :create, Family)
      refute Authorization.can?(scope_for(:editor), :read, Account)
    end

    test "returns false for nil scope" do
      refute Authorization.can?(nil, :read, Family)
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/ancestry/authorization_test.exs`
Expected: FAIL — `can?/3` is undefined

- [ ] **Step 3: Add `can?/3` to the authorization module**

Update `lib/ancestry/authorization.ex`:

```elixir
defmodule Ancestry.Authorization do
  @moduledoc "Ties Permit permissions to the application."
  use Permit, permissions_module: Ancestry.Permissions

  @doc """
  Checks whether the given scope has permission to perform `action` on `resource`.

  Wraps Permit's `can/1 |> do?/2` for convenient use in templates:

      <%= if can?(@current_scope, :index, Account) do %>
        ...
      <% end %>
  """
  def can?(nil, _action, _resource), do: false

  def can?(scope, action, resource) do
    can(scope) |> do?(action, resource)
  end
end
```

- [ ] **Step 4: Import `can?/3` in `lib/web.ex`**

Add to the `html_helpers/0` function:

```elixir
import Ancestry.Authorization, only: [can?: 3]
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/ancestry/authorization_test.exs`
Expected: All pass

- [ ] **Step 6: Commit**

```bash
git add lib/ancestry/authorization.ex lib/web.ex test/ancestry/authorization_test.exs
git commit -m "feat: add can?/3 template helper for Permit authorization"
```

---

### Task 3: Replace Scattered Role Checks in Templates

**Files:**
- Modify: `lib/web/components/layouts.ex:76`
- Modify: `lib/web/components/nav_drawer.ex:98`

- [ ] **Step 1: Replace role check in `layouts.ex`**

In `lib/web/components/layouts.ex`, replace:

```elixir
<%= if @current_scope.account.role == :admin do %>
```

with:

```elixir
<%= if can?(@current_scope, :index, Ancestry.Identity.Account) do %>
```

- [ ] **Step 2: Replace role check in `nav_drawer.ex`**

In `lib/web/components/nav_drawer.ex`, replace:

```elixir
<%= if @current_scope && @current_scope.account && @current_scope.account.role == :admin do %>
```

with:

```elixir
<%= if can?(@current_scope, :index, Ancestry.Identity.Account) do %>
```

- [ ] **Step 3: Run existing tests**

Run: `mix test`
Expected: All pass — behavior unchanged, admin still sees the link, non-admin doesn't.

- [ ] **Step 4: Commit**

```bash
git add lib/web/components/layouts.ex lib/web/components/nav_drawer.ex
git commit -m "refactor: replace inline role checks with can?/3 in navigation"
```

---

### Task 4: Run Precommit

- [ ] **Step 1: Run precommit checks**

Run: `mix precommit`
Expected: Compiles with no warnings, formatted, all tests pass.

- [ ] **Step 2: Fix any issues found**

Address warnings or test failures.

- [ ] **Step 3: Commit any fixes**

---

## Future Work (Not In This Plan)

These tasks are documented in the design spec (`docs/plans/2026-04-13-centralized-authorization-design.md`) for incremental adoption:

1. **Migrate org-scoped LiveViews** — Add `use Permit.Phoenix.LiveView` with `base_query` to scope queries by org. Removes manual `organization_id` boundary checks. Do per-LiveView as you touch them.

2. **Simplify `EnsureOrganization`** — Once all org-scoped LiveViews use `base_query`, remove `account_has_org_access?` call from the hook. Keep org loading into `current_scope`.

3. **Remove `account_has_org_access?/2`** — Once `EnsureOrganization` no longer calls it, deprecate and remove.

4. **Enforce viewer/editor distinction** — Currently all non-admin roles have identical behavior. As LiveViews adopt Permit, viewer restrictions (read-only) will be enforced automatically by the permission rules defined in Task 1.
