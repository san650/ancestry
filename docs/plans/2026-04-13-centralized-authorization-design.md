# Centralized Authorization via Permit

**Date:** 2026-04-13
**Status:** Approved
**Approach:** Approach A — Permit at the LiveView layer only

## Overview

Replace scattered authorization checks (inline role comparisons, `account_has_org_access?/2`, manual org boundary raises) with centralized Permit rules. Authorization decisions live in `Ancestry.Permissions.can/1`, enforced at the LiveView layer via `Permit.Phoenix.LiveView`, and queried in templates via `can?/3`.

Context functions remain authorization-free — they are pure data operations. Business invariants (e.g., cannot deactivate self, last admin guard) stay in contexts as domain rules, not authorization.

Rollout is incremental: adopt per-LiveView as you touch them.

## Permission Rules

All authorization decisions are defined in `Ancestry.Permissions.can/1` by pattern-matching on `Scope`:

```elixir
defmodule Ancestry.Permissions do
  use Permit.Permissions, actions_module: Ancestry.Actions

  alias Ancestry.Identity.{Account, Scope}
  alias Ancestry.Families.Family
  alias Ancestry.People.Person
  alias Ancestry.Galleries.{Gallery, Photo}
  alias Ancestry.Organizations.Organization

  # Admins — full access to everything
  def can(%Scope{account: %Account{role: :admin}}) do
    permit()
    |> all(Account)
    |> all(Organization)
    |> all(Family)
    |> all(Person)
    |> all(Gallery)
    |> all(Photo)
  end

  # Editors — read + write on content resources, no account/org management
  def can(%Scope{account: %Account{role: :editor}}) do
    permit()
    |> all(Family)
    |> all(Person)
    |> all(Gallery)
    |> all(Photo)
    |> read(Organization)
  end

  # Viewers — read-only on content resources
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

### Role matrix

| Action | Viewer | Editor | Admin |
|--------|--------|--------|-------|
| Browse families, people, galleries | yes | yes | yes |
| Add/edit/delete photos, people, families | no | yes | yes |
| Manage accounts, orgs | no | no | yes |

## LiveView Integration

Each LiveView that needs authorization uses `Permit.Phoenix.LiveView` with `resource_module` pointing to its primary schema.

For org-scoped LiveViews, the `base_query/1` callback scopes queries to the current organization, replacing the 15 duplicated manual boundary checks:

```elixir
defmodule Web.FamilyLive.Show do
  use Web, :live_view

  use Permit.Phoenix.LiveView,
    authorization_module: Ancestry.Authorization,
    resource_module: Ancestry.Families.Family,
    scope_subject: &Function.identity/1

  @impl true
  def base_query(%{socket: socket}) do
    org = socket.assigns.current_scope.organization

    from(f in Family, where: f.organization_id == ^org.id)
  end

  @impl true
  def handle_unauthorized(_action, socket) do
    {:halt,
     socket
     |> put_flash(:error, "You don't have permission to access this page")
     |> push_navigate(to: ~p"/org/#{socket.assigns.current_scope.organization}")}
  end
end
```

Permit loads the record via `base_query`, so if the resource doesn't belong to the org, it's a `:not_found` — no manual raise needed.

Shared boilerplate (authorization_module, scope_subject, handle_unauthorized) goes in `lib/web.ex`'s `live_view/0` quote block or a shared module, so each LiveView only specifies `resource_module` and `base_query`.

## Template Authorization

Replace inline role checks with Permit's `can?/3` helper. Import in `lib/web.ex`:

```elixir
defp html_helpers do
  quote do
    # ... existing imports ...
    import Ancestry.Authorization, only: [can?: 3]
  end
end
```

Usage in templates:

```heex
<%!-- Before: scattered role check --%>
<%= if @current_scope && @current_scope.account && @current_scope.account.role == :admin do %>
  <.link navigate={~p"/admin/accounts"}>Manage accounts</.link>
<% end %>

<%!-- After: declarative permission check --%>
<%= if can?(@current_scope, :index, Account) do %>
  <.link navigate={~p"/admin/accounts"}>Manage accounts</.link>
<% end %>
```

Works for any action/resource:
- `can?(@current_scope, :create, Family)` — show "New family" button
- `can?(@current_scope, :delete, Photo)` — show delete icon
- `can?(@current_scope, :index, Account)` — show admin nav link

## Migration Plan

| Current pattern | Replaced by | When |
|---|---|---|
| `Organizations.account_has_org_access?/2` | Permit rules + `base_query` scoping | When org-scoped LiveViews are migrated |
| `EnsureOrganization` calling `account_has_org_access?` | `base_query` scoping; `EnsureOrganization` still loads org into scope | Drop access check from hook |
| 15 manual `family.organization_id != ...` raises | `base_query` returns `:not_found` automatically | Per-LiveView migration |
| `if @current_scope.account.role == :admin` in templates | `can?(@current_scope, :action, Resource)` | Per-template migration |
| `Organizations.list_organizations_for_account/1` admin bypass | Permit rule: admins get `all(Organization)` | When org picker is migrated |

### What stays

- **`EnsureOrganization` on_mount hook** — still loads org into `current_scope.organization`. Stops doing access check.
- **Context functions** — remain authorization-free. Permit enforces at the LiveView boundary.
- **Business invariants** (`cannot_deactivate_self`, `last_admin`) — domain rules, not authorization. Stay in `Identity` context.

## Anti-Patterns to Avoid

These patterns are explicitly banned going forward:

1. **Inline role checks in templates:** `if @current_scope.account.role == :admin` — use `can?/3`
2. **Hardcoded role bypasses in contexts:** `def foo(%Account{role: :admin}, _), do: true` — define in `Permissions`
3. **Manual org boundary checks in mount:** `if resource.organization_id != scope.organization.id` — use `base_query`
4. **Duplicated handle_unauthorized:** Use shared module or `lib/web.ex` quote block
