# Audit Log Admin Views Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build read-only super-admin UI over the existing `audit_log` table: top-level index, org-scoped index, and detail page with `correlation_id` grouping. Real-time updates via PubSub. Infinite scroll + organization/account filters. No new schema, no migrations.

**Architecture:** Three Phoenix LiveViews share a function-component module for the table, filter bar, and viewport sentinel. A new `Ancestry.Audit` query-only context wraps the table. Real-time broadcasts come out of `Ancestry.Bus` itself (not handlers) on two PubSub topics: `"audit_log"` and `"audit_log:org:#{id}"`. Authorization is a single `all(Ancestry.Audit.Log)` rule in `Ancestry.Permissions` for `:admin`.

**Tech Stack:** Elixir, Phoenix 1.8 LiveView, Ecto, Permit 0.3.x, Phoenix.PubSub, Postgres, ExUnit, PhoenixTest.Playwright (E2E).

**Spec:** `docs/plans/2026-05-09-audit-log-admin-views.md`. Read it before starting.

**Branch:** `audit-log` (already checked out). All commits land directly on this branch.

**Conventions:**
- TDD per task: write test → run → fail → implement → run → pass → commit.
- `mix format` before each commit.
- `mix compile --warnings-as-errors` must pass before each commit.
- `mix test` for the affected files passes before each commit.
- Final phase runs `mix precommit`.
- Commit messages match recent log style (`Add ...`, `Wire ...`, `Render ...`).
- Follow `test/CLAUDE.md` and `test/user_flows/CLAUDE.md` for test patterns.
- Use `test_id/1` (never raw `data-testid`) in templates.
- Visible strings go through `gettext/1`. Translations land in Phase 6.

---

## Phase 0 — Backend: permissions + queries

Goal: data layer and authorization rule are in place and fully tested before any UI work.

---

### Task 0.1: Permit rule for `Ancestry.Audit.Log`

**Files:**
- Modify: `lib/ancestry/permissions.ex`
- Modify: `test/ancestry/permissions_test.exs`

- [ ] **Step 1: Inspect existing Permit tests**

```bash
sed -n '1,80p' test/ancestry/permissions_test.exs
```

Note the pattern (e.g. `assert can?(scope_for(:admin), :index, Account)`).

- [ ] **Step 2: Write failing tests**

Append to `test/ancestry/permissions_test.exs` (inside the existing test module, in a new `describe` block):

```elixir
describe "audit log access" do
  alias Ancestry.Audit.Log

  test "admin can index and show audit logs" do
    scope = scope_for(:admin)
    assert can?(scope, :index, Log)
    assert can?(scope, :show, Log)
  end

  test "editor cannot access audit logs" do
    scope = scope_for(:editor)
    refute can?(scope, :index, Log)
    refute can?(scope, :show, Log)
  end

  test "viewer cannot access audit logs" do
    scope = scope_for(:viewer)
    refute can?(scope, :index, Log)
    refute can?(scope, :show, Log)
  end
end
```

If `scope_for/1` doesn't exist in the test file, mirror whatever helper the existing tests use to build a `Scope` with a given role.

- [ ] **Step 3: Run tests, expect failure**

```bash
mix test test/ancestry/permissions_test.exs
```

Expected: the new admin assertions fail (no `Audit.Log` rule yet).

- [ ] **Step 4: Add Permit rule**

In `lib/ancestry/permissions.ex`, in the `def can(%Scope{account: %Account{role: :admin}})` clause, add `|> all(Ancestry.Audit.Log)`. Also add `alias Ancestry.Audit.Log` at the top.

```elixir
alias Ancestry.Audit.Log
# ...
def can(%Scope{account: %Account{role: :admin}}) do
  permit()
  |> all(Account)
  |> all(Organization)
  |> all(Family)
  |> all(Person)
  |> all(Gallery)
  |> all(Photo)
  |> all(PhotoComment)
  |> all(Log)
end
```

- [ ] **Step 5: Run tests, expect pass**

```bash
mix test test/ancestry/permissions_test.exs
```

Expected: all green.

- [ ] **Step 6: Format + commit**

```bash
mix format lib/ancestry/permissions.ex test/ancestry/permissions_test.exs
git add lib/ancestry/permissions.ex test/ancestry/permissions_test.exs
git commit -m "Permit super-admin to read Audit.Log"
```

---

### Task 0.2: `Ancestry.Audit.list_entries/2` query

**Files:**
- Create: `lib/ancestry/audit.ex`
- Create: `test/ancestry/audit_test.exs`

- [ ] **Step 1: Confirm a factory exists for audit logs**

```bash
grep -n ":audit_log\|audit_log_factory" test/support/factory.ex
```

If absent, add to `test/support/factory.ex`:

```elixir
def audit_log_factory do
  %Ancestry.Audit.Log{
    command_id: "cmd-#{Ecto.UUID.generate()}",
    correlation_id: "req-#{Ecto.UUID.generate()}",
    command_module: "Ancestry.Commands.AddCommentToPhoto",
    account_id: 1,
    account_name: "Tester",
    account_email: sequence(:audit_email, &"audit#{&1}@example.com"),
    organization_id: nil,
    organization_name: nil,
    payload: %{"photo_id" => 1, "text" => "hi"}
  }
end
```

If you add the factory, format and `git add test/support/factory.ex`. (Commit goes with this task at the end.)

- [ ] **Step 2: Write failing tests**

Create `test/ancestry/audit_test.exs`:

```elixir
defmodule Ancestry.AuditTest do
  use Ancestry.DataCase, async: true
  alias Ancestry.Audit

  describe "list_entries/2" do
    test "returns rows newest first" do
      old = insert(:audit_log, inserted_at: ~N[2026-05-01 10:00:00])
      new = insert(:audit_log, inserted_at: ~N[2026-05-09 10:00:00])

      assert [r1, r2] = Audit.list_entries(%{}, 50)
      assert r1.id == new.id
      assert r2.id == old.id
    end

    test "filters by organization_id" do
      org_a = insert(:organization)
      org_b = insert(:organization)
      a = insert(:audit_log, organization_id: org_a.id)
      _b = insert(:audit_log, organization_id: org_b.id)

      assert [row] = Audit.list_entries(%{organization_id: org_a.id}, 50)
      assert row.id == a.id
    end

    test "filters by account_id" do
      acc = insert(:account)
      mine = insert(:audit_log, account_id: acc.id)
      _other = insert(:audit_log, account_id: acc.id + 9999)

      assert [row] = Audit.list_entries(%{account_id: acc.id}, 50)
      assert row.id == mine.id
    end

    test "respects limit" do
      Enum.each(1..5, fn _ -> insert(:audit_log) end)
      assert length(Audit.list_entries(%{}, 3)) == 3
    end

    test "cursor returns strictly older rows" do
      r1 = insert(:audit_log, inserted_at: ~N[2026-05-09 10:00:00])
      r2 = insert(:audit_log, inserted_at: ~N[2026-05-08 10:00:00])
      r3 = insert(:audit_log, inserted_at: ~N[2026-05-07 10:00:00])

      cursor = {r1.inserted_at, r1.id}

      ids = Audit.list_entries(%{before: cursor}, 50) |> Enum.map(& &1.id)
      assert ids == [r2.id, r3.id]
    end

    test "cursor with same-second rows uses id as tiebreaker" do
      ts = ~N[2026-05-09 10:00:00]
      a = insert(:audit_log, inserted_at: ts)
      b = insert(:audit_log, inserted_at: ts)
      [first, second] = if a.id < b.id, do: [b, a], else: [a, b]

      cursor = {first.inserted_at, first.id}
      assert [^second] = Audit.list_entries(%{before: cursor}, 50)
    end
  end
end
```

- [ ] **Step 3: Run tests, expect failure**

```bash
mix test test/ancestry/audit_test.exs
```

Expected: `Ancestry.Audit` is undefined.

- [ ] **Step 4: Implement `Ancestry.Audit.list_entries/2`**

Create `lib/ancestry/audit.ex`:

```elixir
defmodule Ancestry.Audit do
  @moduledoc """
  Read-only queries over the `audit_log` table. Mutations flow through
  `Ancestry.Bus` exclusively.
  """

  import Ecto.Query

  alias Ancestry.Audit.Log
  alias Ancestry.Repo

  @default_limit 50

  @doc """
  Lists audit-log entries newest first. Filters: `:organization_id`, `:account_id`,
  `:before` (a `{NaiveDateTime, id}` cursor — only rows strictly older are returned).
  """
  def list_entries(filters, limit \\ @default_limit) when is_map(filters) do
    Log
    |> apply_filter(:organization_id, filters)
    |> apply_filter(:account_id, filters)
    |> apply_cursor(filters)
    |> order_by([l], desc: l.inserted_at, desc: l.id)
    |> limit(^limit)
    |> Repo.all()
  end

  defp apply_filter(query, :organization_id, %{organization_id: id}) when not is_nil(id),
    do: where(query, [l], l.organization_id == ^id)

  defp apply_filter(query, :account_id, %{account_id: id}) when not is_nil(id),
    do: where(query, [l], l.account_id == ^id)

  defp apply_filter(query, _key, _filters), do: query

  defp apply_cursor(query, %{before: {ts, id}}) when not is_nil(ts) and not is_nil(id) do
    where(query, [l], {l.inserted_at, l.id} < {^ts, ^id})
  end

  defp apply_cursor(query, _filters), do: query
end
```

Note the Postgres tuple-compare clause `{l.inserted_at, l.id} < {^ts, ^id}`. Ecto compiles tuples to row-wise comparison.

- [ ] **Step 5: Run tests, expect pass**

```bash
mix test test/ancestry/audit_test.exs
```

Expected: all green.

- [ ] **Step 6: Format + commit**

```bash
mix format lib/ancestry/audit.ex test/ancestry/audit_test.exs test/support/factory.ex
git add lib/ancestry/audit.ex test/ancestry/audit_test.exs test/support/factory.ex
git commit -m "Add Ancestry.Audit query module with list_entries/2"
```

---

### Task 0.3: `list_correlated_entries/1` and `list_audit_accounts/1`

**Files:**
- Modify: `lib/ancestry/audit.ex`
- Modify: `test/ancestry/audit_test.exs`

- [ ] **Step 1: Write failing tests**

Append to `test/ancestry/audit_test.exs` inside the module:

```elixir
describe "list_correlated_entries/1" do
  test "returns sibling rows in chronological order, including the focal row" do
    cid = "req-#{Ecto.UUID.generate()}"
    a = insert(:audit_log, correlation_id: cid, inserted_at: ~N[2026-05-09 10:00:00])
    b = insert(:audit_log, correlation_id: cid, inserted_at: ~N[2026-05-09 10:00:01])
    _other = insert(:audit_log, correlation_id: "req-other")

    ids = Audit.list_correlated_entries(cid) |> Enum.map(& &1.id)
    assert ids == [a.id, b.id]
  end

  test "returns single row when no siblings" do
    cid = "req-solo-#{Ecto.UUID.generate()}"
    only = insert(:audit_log, correlation_id: cid)

    assert [row] = Audit.list_correlated_entries(cid)
    assert row.id == only.id
  end
end

describe "list_audit_accounts/1" do
  test "returns DISTINCT (account_id, account_email) tuples" do
    acc = insert(:account, email: "a@example.com")
    insert(:audit_log, account_id: acc.id, account_email: acc.email)
    insert(:audit_log, account_id: acc.id, account_email: acc.email)

    assert [%{id: id, email: "a@example.com"}] = Audit.list_audit_accounts(%{})
    assert id == acc.id
  end

  test "scopes to organization_id when provided" do
    org_a = insert(:organization)
    org_b = insert(:organization)
    acc_a = insert(:account, email: "a@x.com")
    acc_b = insert(:account, email: "b@x.com")

    insert(:audit_log,
      account_id: acc_a.id,
      account_email: acc_a.email,
      organization_id: org_a.id
    )

    insert(:audit_log,
      account_id: acc_b.id,
      account_email: acc_b.email,
      organization_id: org_b.id
    )

    assert [%{id: id}] = Audit.list_audit_accounts(%{organization_id: org_a.id})
    assert id == acc_a.id
  end

  test "returns [] when no rows" do
    assert [] = Audit.list_audit_accounts(%{})
  end
end
```

- [ ] **Step 2: Run tests, expect failure**

```bash
mix test test/ancestry/audit_test.exs
```

Expected: `list_correlated_entries/1` and `list_audit_accounts/1` undefined.

- [ ] **Step 3: Implement both functions**

Append to `lib/ancestry/audit.ex` inside the module:

```elixir
@doc "Every row sharing `correlation_id`, oldest first."
def list_correlated_entries(correlation_id) when is_binary(correlation_id) do
  Log
  |> where([l], l.correlation_id == ^correlation_id)
  |> order_by([l], asc: l.inserted_at, asc: l.id)
  |> Repo.all()
end

@doc """
Distinct `%{id, email}` of accounts that have appeared in the audit log.
Optionally scoped to an organization via `:organization_id`.
"""
def list_audit_accounts(filters) when is_map(filters) do
  Log
  |> apply_filter(:organization_id, filters)
  |> select([l], %{id: l.account_id, email: l.account_email})
  |> distinct(true)
  |> order_by([l], asc: l.account_email)
  |> Repo.all()
end
```

- [ ] **Step 4: Run tests, expect pass**

```bash
mix test test/ancestry/audit_test.exs
```

- [ ] **Step 5: Format + commit**

```bash
mix format lib/ancestry/audit.ex test/ancestry/audit_test.exs
git add lib/ancestry/audit.ex test/ancestry/audit_test.exs
git commit -m "Add list_correlated_entries/1 and list_audit_accounts/1"
```

---

## Phase 1 — Real-time broadcasts

Goal: every successful `Bus.dispatch` broadcasts the audit row on two PubSub topics. Failed dispatches broadcast nothing.

---

### Task 1.1: Bus broadcasts the audit row post-commit

**Files:**
- Modify: `lib/ancestry/bus.ex`
- Modify: `test/ancestry/bus_test.exs` (or create `test/ancestry/bus_audit_broadcast_test.exs` if it keeps the file under control)

- [ ] **Step 1: Locate `bus_test.exs` and inspect existing dispatch tests**

```bash
sed -n '1,60p' test/ancestry/bus_test.exs
grep -n "describe\|test " test/ancestry/bus_test.exs | head -20
```

Pick an existing happy-path test to model the new one on. You'll need a command that already exists (e.g. `Ancestry.Commands.AddCommentToPhoto`) plus its handler so the dispatcher actually commits a row.

- [ ] **Step 2: Write failing tests**

Add a `describe "audit broadcast"` block to `test/ancestry/bus_test.exs`. Adjust factories/setup to whatever the existing tests use:

```elixir
describe "audit broadcast" do
  setup do
    # Assemble a real, dispatchable scenario. Use existing factory helpers.
    photo = insert(:photo, status: "processed")
    account = insert(:account, role: :admin)
    organization = photo.gallery.family.organization

    scope = %Ancestry.Identity.Scope{account: account, organization: organization}
    %{scope: scope, photo: photo, organization: organization}
  end

  test "broadcasts on global topic when dispatch succeeds", %{scope: scope, photo: photo} do
    Phoenix.PubSub.subscribe(Ancestry.PubSub, "audit_log")

    {:ok, cmd} = Ancestry.Commands.AddCommentToPhoto.new(%{photo_id: photo.id, text: "hi"})
    assert {:ok, _} = Ancestry.Bus.dispatch(scope, cmd)

    assert_receive {:audit_logged, %Ancestry.Audit.Log{} = row}, 1_000
    assert row.account_id == scope.account.id
    assert row.command_module == "Ancestry.Commands.AddCommentToPhoto"
  end

  test "broadcasts on org topic when scope has an organization", %{
    scope: scope,
    photo: photo,
    organization: organization
  } do
    Phoenix.PubSub.subscribe(Ancestry.PubSub, "audit_log:org:#{organization.id}")

    {:ok, cmd} = Ancestry.Commands.AddCommentToPhoto.new(%{photo_id: photo.id, text: "hi"})
    assert {:ok, _} = Ancestry.Bus.dispatch(scope, cmd)

    assert_receive {:audit_logged, %Ancestry.Audit.Log{} = row}, 1_000
    assert row.organization_id == organization.id
  end

  test "no broadcast when dispatch is unauthorized" do
    viewer = insert(:account, role: :viewer)
    photo = insert(:photo)
    scope = %Ancestry.Identity.Scope{account: viewer, organization: photo.gallery.family.organization}

    Phoenix.PubSub.subscribe(Ancestry.PubSub, "audit_log")

    {:ok, cmd} = Ancestry.Commands.RemovePhotoFromGallery.new(%{photo_id: photo.id})
    assert {:error, :unauthorized} = Ancestry.Bus.dispatch(scope, cmd)

    refute_receive {:audit_logged, _}, 200
  end

  test "no broadcast when handler step fails (e.g. :not_found)" do
    photo = insert(:photo)
    admin = insert(:account, role: :admin)

    scope = %Ancestry.Identity.Scope{
      account: admin,
      organization: photo.gallery.family.organization
    }

    Phoenix.PubSub.subscribe(Ancestry.PubSub, "audit_log")

    # Pick a command + handler that returns {:error, :not_found} when the
    # target row doesn't exist. RemoveCommentFromPhoto with a bogus id is
    # a good fit — adjust to whatever existing handler has a clean
    # `:not_found` path in this codebase.
    {:ok, bad_cmd} = Ancestry.Commands.RemoveCommentFromPhoto.new(%{photo_comment_id: -1})
    assert {:error, :not_found} = Ancestry.Bus.dispatch(scope, bad_cmd)

    refute_receive {:audit_logged, _}, 200
  end
end
```

If the surrounding test module doesn't already `import Ancestry.Factory`, add it. If `:photo` factory builds without an organization, adjust the setup accordingly.

- [ ] **Step 3: Run tests, expect failure**

```bash
mix test test/ancestry/bus_test.exs
```

Expected: the new four tests fail (no broadcast wired up yet).

- [ ] **Step 4: Wire the broadcast in `Ancestry.Bus`**

Modify `lib/ancestry/bus.ex`. The existing `run/2` returns the primary step on success. Change it to also broadcast the audit row before returning. Use the row already inserted by `Step.audit/0` (it lives at `changes[:audit]`).

```elixir
defp run(env, module) do
  case module.handled_by().handle(env) do
    {:ok, changes} ->
      broadcast_audit(changes[:audit])
      Enum.each(changes[:effects] || [], &run_effect/1)
      {:ok, Map.fetch!(changes, module.primary_step())}

    # ...rest unchanged...
  end
end

defp broadcast_audit(nil), do: :ok

defp broadcast_audit(%Ancestry.Audit.Log{} = row) do
  Phoenix.PubSub.broadcast(Ancestry.PubSub, "audit_log", {:audit_logged, row})

  if row.organization_id do
    Phoenix.PubSub.broadcast(
      Ancestry.PubSub,
      "audit_log:org:#{row.organization_id}",
      {:audit_logged, row}
    )
  end

  :ok
end
```

The `nil` clause guards against any (hypothetical) future handler that bypasses `Step.audit/0`. Today every handler appends `Step.audit()`.

- [ ] **Step 5: Run tests, expect pass**

```bash
mix test test/ancestry/bus_test.exs
```

Then run the full suite to make sure nothing else broke:

```bash
mix test
```

- [ ] **Step 6: Format + commit**

```bash
mix format lib/ancestry/bus.ex test/ancestry/bus_test.exs
git add lib/ancestry/bus.ex test/ancestry/bus_test.exs
git commit -m "Broadcast {:audit_logged, row} on global and per-org PubSub topics"
```

---

## Phase 2 — Top-level Index page

Goal: `/admin/audit-log` lists every audit row with filters, infinite scroll, inline expand, and live updates.

---

### Task 2.1: Add `/admin/audit-log` route + skeleton LiveView

**Files:**
- Create: `lib/web/live/audit_log_live/index.ex`
- Modify: `lib/web/router.ex`

- [ ] **Step 1: Add the route**

In `lib/web/router.ex`, inside the `live_session :admin` block (next to the existing `live "/admin/accounts", ...` lines), add:

```elixir
live "/admin/audit-log", AuditLogLive.Index, :index
```

- [ ] **Step 2: Create skeleton LiveView**

Create `lib/web/live/audit_log_live/index.ex`:

```elixir
defmodule Web.AuditLogLive.Index do
  use Web, :live_view

  use Permit.Phoenix.LiveView,
    authorization_module: Ancestry.Authorization,
    resource_module: Ancestry.Audit.Log,
    scope_subject: &Function.identity/1,
    skip_preload: [:index]

  alias Ancestry.Audit

  @impl true
  def handle_unauthorized(_action, socket) do
    {:halt,
     socket
     |> put_flash(:error, gettext("You don't have permission to access this page"))
     |> push_navigate(to: ~p"/org")}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Audit log"))
     |> stream(:entries, [])}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6" {test_id("audit-log")}>
        <h1 class="font-cm-display text-cm-indigo text-lg uppercase">
          {gettext("Audit log")}
        </h1>
      </div>
    </Layouts.app>
    """
  end
end
```

- [ ] **Step 3: Verify compile**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 4: Smoke-check the route serves**

```bash
mix test test/ancestry/permissions_test.exs
```

(No new test needed yet — Task 2.2 adds the first E2E.)

- [ ] **Step 5: Format + commit**

```bash
mix format lib/web/router.ex lib/web/live/audit_log_live/index.ex
git add lib/web/router.ex lib/web/live/audit_log_live/index.ex
git commit -m "Wire skeleton /admin/audit-log LiveView"
```

---

### Task 2.2: Render audit rows in a stream

**Files:**
- Modify: `lib/web/live/audit_log_live/index.ex`
- Create: `lib/web/live/audit_log_live/components.ex`
- Create: `test/user_flows/audit_log_test.exs`

- [ ] **Step 1: Write failing E2E tests**

Create `test/user_flows/audit_log_test.exs`:

```elixir
defmodule Web.UserFlows.AuditLogTest do
  use Web.E2ECase

  # Given audit-log rows exist for two organizations
  # When a super-admin visits /admin/audit-log
  # Then they see all rows newest first

  setup do
    org_a = insert(:organization, name: "Alpha")
    org_b = insert(:organization, name: "Beta")

    row_a =
      insert(:audit_log,
        organization_id: org_a.id,
        organization_name: org_a.name,
        account_email: "ana@example.com",
        command_module: "Ancestry.Commands.AddCommentToPhoto",
        inserted_at: ~N[2026-05-09 10:00:00]
      )

    row_b =
      insert(:audit_log,
        organization_id: org_b.id,
        organization_name: org_b.name,
        account_email: "bob@example.com",
        command_module: "Ancestry.Commands.AddPhotoToGallery",
        inserted_at: ~N[2026-05-08 10:00:00]
      )

    %{org_a: org_a, org_b: org_b, row_a: row_a, row_b: row_b}
  end

  test "admin sees all audit rows", %{conn: conn, row_a: a, row_b: b} do
    conn
    |> log_in_e2e(role: :admin)
    |> visit(~p"/admin/audit-log")
    |> assert_has(test_id("audit-row-#{a.id}"))
    |> assert_has(test_id("audit-row-#{b.id}"))
    |> assert_has(test_id("audit-row-#{a.id}"), text: "AddCommentToPhoto")
    |> assert_has(test_id("audit-row-#{a.id}"), text: "ana@example.com")
    |> assert_has(test_id("audit-row-#{a.id}"), text: "Alpha")
  end

  test "editor cannot access /admin/audit-log", %{conn: conn} do
    conn
    |> log_in_e2e(role: :editor)
    |> visit(~p"/admin/audit-log")
    |> assert_path("/org")
    |> assert_has("*", text: "permission")
  end
end
```

- [ ] **Step 2: Run, expect failure**

```bash
mix test test/user_flows/audit_log_test.exs
```

Expected: rows aren't rendered yet.

- [ ] **Step 3: Build the shared components module**

Create `lib/web/live/audit_log_live/components.ex`:

```elixir
defmodule Web.AuditLogLive.Components do
  @moduledoc "Shared function components for the audit-log LiveViews."
  use Phoenix.Component
  use Gettext, backend: Web.Gettext

  import Web.Helpers.TestHelpers

  attr :id, :string, default: "audit-table"
  attr :stream, :any, required: true
  attr :expanded_id, :any, default: nil

  def audit_table(assigns) do
    ~H"""
    <div id={@id} phx-update="stream" {test_id("audit-table")}>
      <div :for={{dom_id, row} <- @stream} id={dom_id} {test_id("audit-row-#{row.id}")}>
        <button
          type="button"
          phx-click="toggle"
          phx-value-id={row.id}
          class="w-full grid grid-cols-12 gap-2 items-start px-4 py-3 border-b border-cm-border/20 text-left hover:bg-cm-surface"
        >
          <span class="col-span-2 font-cm-mono text-[11px] text-cm-text-muted">
            {Calendar.strftime(row.inserted_at, "%Y-%m-%d %H:%M:%S")}
          </span>
          <span class="col-span-3 font-cm-mono text-[11px]">{row.account_email}</span>
          <span class="col-span-2 font-cm-mono text-[11px]">
            {row.organization_name || "—"}
          </span>
          <span class="col-span-2 font-cm-mono text-[11px] font-bold">
            {short_command(row.command_module)}
          </span>
          <span class="col-span-3 font-cm-mono text-[10px] text-cm-text-muted truncate">
            {payload_preview(row.payload)}
          </span>
        </button>

        <div :if={@expanded_id == row.id} class="px-4 py-3 bg-cm-surface text-[11px] font-cm-mono">
          <div><strong>command_id:</strong> {row.command_id}</div>
          <div><strong>correlation_id:</strong> {row.correlation_id}</div>
          <pre class="whitespace-pre-wrap break-all">{Jason.encode!(row.payload, pretty: true)}</pre>
          <.link
            navigate={"/admin/audit-log/#{row.id}"}
            class="text-cm-coral underline"
            {test_id("audit-row-open-#{row.id}")}
          >
            {gettext("Open")}
          </.link>
        </div>
      </div>
    </div>
    """
  end

  defp short_command(mod) when is_binary(mod) do
    mod |> String.split(".") |> List.last()
  end

  defp payload_preview(payload) do
    json = Jason.encode!(payload)
    if String.length(json) > 120, do: String.slice(json, 0, 117) <> "...", else: json
  end
end
```

- [ ] **Step 4: Wire `Index` to load + render rows**

Replace the body of `mount/3` and `render/1` in `lib/web/live/audit_log_live/index.ex`:

```elixir
alias Web.AuditLogLive.Components

@limit 50

@impl true
def mount(_params, _session, socket) do
  rows = Audit.list_entries(%{}, @limit)

  {:ok,
   socket
   |> assign(:page_title, gettext("Audit log"))
   |> assign(:expanded_id, nil)
   |> stream(:entries, rows)}
end

@impl true
def render(assigns) do
  ~H"""
  <Layouts.app flash={@flash} current_scope={@current_scope}>
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
      <h1 class="font-cm-display text-cm-indigo text-lg uppercase pb-4">
        {gettext("Audit log")}
      </h1>
      <Components.audit_table stream={@streams.entries} expanded_id={@expanded_id} />
    </div>
  </Layouts.app>
  """
end

@impl true
def handle_event("toggle", %{"id" => id}, socket) do
  id = String.to_integer(id)
  next = if socket.assigns.expanded_id == id, do: nil, else: id
  {:noreply, assign(socket, :expanded_id, next)}
end
```

- [ ] **Step 5: Run, expect pass**

```bash
mix test test/user_flows/audit_log_test.exs
```

- [ ] **Step 6: Format + commit**

```bash
mix format lib/web/live/audit_log_live/index.ex lib/web/live/audit_log_live/components.ex test/user_flows/audit_log_test.exs
git add lib/web/live/audit_log_live/index.ex lib/web/live/audit_log_live/components.ex test/user_flows/audit_log_test.exs
git commit -m "Render audit-log table on /admin/audit-log"
```

---

### Task 2.3: Filter bar (organization + account)

**Files:**
- Modify: `lib/web/live/audit_log_live/index.ex`
- Modify: `lib/web/live/audit_log_live/components.ex`
- Modify: `test/user_flows/audit_log_test.exs`

- [ ] **Step 1: Write failing E2E tests**

Append to `test/user_flows/audit_log_test.exs`:

```elixir
test "filter by organization narrows results", %{conn: conn, org_a: org_a, row_a: a, row_b: b} do
  conn
  |> log_in_e2e(role: :admin)
  |> visit(~p"/admin/audit-log")
  |> select(label: "Organization", option: "Alpha")
  |> wait_liveview()
  |> assert_has(test_id("audit-row-#{a.id}"))
  |> refute_has(test_id("audit-row-#{b.id}"))
  |> assert_has("*", text: "organization_id=#{org_a.id}")
end

test "filter by account narrows results", %{conn: conn, row_a: a, row_b: b} do
  conn
  |> log_in_e2e(role: :admin)
  |> visit(~p"/admin/audit-log")
  |> select(label: "Account", option: "ana@example.com")
  |> wait_liveview()
  |> assert_has(test_id("audit-row-#{a.id}"))
  |> refute_has(test_id("audit-row-#{b.id}"))
end

test "combined filters compose", %{conn: conn, row_a: a, row_b: b} do
  conn
  |> log_in_e2e(role: :admin)
  |> visit(~p"/admin/audit-log")
  |> select(label: "Organization", option: "Alpha")
  |> wait_liveview()
  |> select(label: "Account", option: "ana@example.com")
  |> wait_liveview()
  |> assert_has(test_id("audit-row-#{a.id}"))
  |> refute_has(test_id("audit-row-#{b.id}"))
end
```

If `assert_path/2` isn't available for query strings, replace the URL assertion with `assert_has("a", text: "Organization")` or similar — the goal is that filter state survives the change.

- [ ] **Step 2: Run, expect failure**

```bash
mix test test/user_flows/audit_log_test.exs
```

- [ ] **Step 3: Add `filter_bar/1` component**

Append to `Web.AuditLogLive.Components`:

```elixir
attr :organizations, :list, required: true
attr :accounts, :list, required: true
attr :filters, :map, required: true
attr :show_organization?, :boolean, default: true

def filter_bar(assigns) do
  ~H"""
  <form
    id="audit-filter"
    phx-change="filter"
    class="flex flex-wrap gap-3 items-end pb-4"
    {test_id("audit-filter")}
  >
    <label :if={@show_organization?} class="flex flex-col text-[11px] font-cm-mono">
      <span class="font-bold uppercase">{gettext("Organization")}</span>
      <select
        name="filters[organization_id]"
        class="border border-cm-border rounded-cm px-2 py-1"
        {test_id("audit-filter-org")}
      >
        <option value="">{gettext("All organizations")}</option>
        <option
          :for={org <- @organizations}
          value={org.id}
          selected={"#{@filters[:organization_id]}" == "#{org.id}"}
        >{org.name}</option>
      </select>
    </label>

    <label class="flex flex-col text-[11px] font-cm-mono">
      <span class="font-bold uppercase">{gettext("Account")}</span>
      <select
        name="filters[account_id]"
        class="border border-cm-border rounded-cm px-2 py-1"
        {test_id("audit-filter-account")}
      >
        <option value="">{gettext("All accounts")}</option>
        <option
          :for={acc <- @accounts}
          value={acc.id}
          selected={"#{@filters[:account_id]}" == "#{acc.id}"}
        >{acc.email}</option>
      </select>
    </label>
  </form>
  """
end
```

- [ ] **Step 4: Wire filters in `Index`**

Update `lib/web/live/audit_log_live/index.ex`:

```elixir
@impl true
def mount(_params, _session, socket) do
  {:ok,
   socket
   |> assign(:page_title, gettext("Audit log"))
   |> assign(:expanded_id, nil)
   |> assign(:filters, %{})
   |> assign(:organizations, Ancestry.Organizations.list_organizations())
   |> assign(:accounts, Audit.list_audit_accounts(%{}))
   |> stream(:entries, [])}
end

@impl true
def handle_params(params, _uri, socket) do
  filters = parse_filters(params)
  rows = Audit.list_entries(filters, @limit)
  accounts = Audit.list_audit_accounts(Map.take(filters, [:organization_id]))

  {:noreply,
   socket
   |> assign(:filters, filters)
   |> assign(:accounts, accounts)
   |> stream(:entries, rows, reset: true)}
end

@impl true
def handle_event("filter", %{"filters" => params}, socket) do
  query =
    params
    |> Enum.reject(fn {_k, v} -> v in [nil, ""] end)
    |> URI.encode_query()

  path = if query == "", do: ~p"/admin/audit-log", else: ~p"/admin/audit-log?#{query}"
  {:noreply, push_patch(socket, to: path)}
end

defp parse_filters(params) do
  %{}
  |> maybe_put(:organization_id, parse_int(params["organization_id"]))
  |> maybe_put(:account_id, parse_int(params["account_id"]))
end

defp maybe_put(map, _key, nil), do: map
defp maybe_put(map, key, val), do: Map.put(map, key, val)

defp parse_int(nil), do: nil
defp parse_int(""), do: nil
defp parse_int(s) when is_binary(s), do: String.to_integer(s)
```

Update `render/1` to call `filter_bar`:

```elixir
def render(assigns) do
  ~H"""
  <Layouts.app flash={@flash} current_scope={@current_scope}>
    <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
      <h1 class="font-cm-display text-cm-indigo text-lg uppercase pb-4">
        {gettext("Audit log")}
      </h1>
      <Components.filter_bar
        organizations={@organizations}
        accounts={@accounts}
        filters={@filters}
      />
      <Components.audit_table stream={@streams.entries} expanded_id={@expanded_id} />
    </div>
  </Layouts.app>
  """
end
```

- [ ] **Step 5: Run, expect pass**

```bash
mix test test/user_flows/audit_log_test.exs
```

If the playwright `select(label: ..., option: ...)` doesn't match because the label text is "Organization" alone (no `:`), tweak the test to use `select(test_id("audit-filter-org"), option: "Alpha")` or whatever shape `Web.E2ECase` actually exposes — check `test/user_flows/account_management_test.exs` for the exact API used elsewhere in this repo.

- [ ] **Step 6: Format + commit**

```bash
mix format lib/web/live/audit_log_live/index.ex lib/web/live/audit_log_live/components.ex test/user_flows/audit_log_test.exs
git add lib/web/live/audit_log_live/index.ex lib/web/live/audit_log_live/components.ex test/user_flows/audit_log_test.exs
git commit -m "Add organization and account filters to audit-log index"
```

---

### Task 2.4: Infinite scroll

**Files:**
- Modify: `lib/web/live/audit_log_live/index.ex`
- Modify: `lib/web/live/audit_log_live/components.ex`
- Modify: `test/user_flows/audit_log_test.exs`

- [ ] **Step 1: Write failing E2E test**

Append to `test/user_flows/audit_log_test.exs`:

```elixir
test "infinite scroll loads older rows", %{conn: conn} do
  # Seed enough rows to exceed the page (limit is 50)
  # The two from setup count toward the total but here we add 60 more.
  Enum.each(1..60, fn i ->
    insert(:audit_log,
      account_email: "user#{i}@example.com",
      inserted_at: NaiveDateTime.add(~N[2026-05-01 10:00:00], -i, :second)
    )
  end)

  conn
  |> log_in_e2e(role: :admin)
  |> visit(~p"/admin/audit-log")
  |> assert_has(test_id("audit-load-more"))
  |> click(test_id("audit-load-more"))
  |> wait_liveview()
  |> assert_has("*", text: "user60@example.com")
  |> refute_has(test_id("audit-load-more"))
end
```

If clicking the sentinel via `click/2` is awkward, switch the trigger to a manually-clickable button (still using `phx-viewport-bottom` in production but with a regular `phx-click` fallback). A button is also more accessible.

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Add `viewport_sentinel/1` component**

Append to `Web.AuditLogLive.Components`:

```elixir
attr :has_more?, :boolean, required: true

def viewport_sentinel(assigns) do
  ~H"""
  <div :if={@has_more?} class="py-6 text-center">
    <button
      type="button"
      phx-click="load_more"
      phx-viewport-bottom="load_more"
      class="font-cm-mono text-[11px] uppercase tracking-wider text-cm-coral underline"
      {test_id("audit-load-more")}
    >
      {gettext("Load more")}
    </button>
  </div>
  """
end
```

- [ ] **Step 4: Wire `load_more` and cursor in `Index`**

Update `lib/web/live/audit_log_live/index.ex`:

- Track `:cursor` and `:has_more?` in assigns. After every fetch, set the cursor to the last row's `(inserted_at, id)` and `has_more?` to whether `length(rows) == @limit`.
- Add `handle_event("load_more", _, socket)` that fetches the next page using `filters |> Map.put(:before, cursor)` and `stream_insert`s each row at the end (or use `stream(socket, :entries, more, at: -1)`).

```elixir
@impl true
def handle_params(params, _uri, socket) do
  filters = parse_filters(params)
  rows = Audit.list_entries(filters, @limit)
  accounts = Audit.list_audit_accounts(Map.take(filters, [:organization_id]))

  {:noreply,
   socket
   |> assign(:filters, filters)
   |> assign(:accounts, accounts)
   |> assign(:cursor, cursor_from(rows))
   |> assign(:has_more?, length(rows) == @limit)
   |> stream(:entries, rows, reset: true)}
end

@impl true
def handle_event("load_more", _, socket) do
  filters = Map.put(socket.assigns.filters, :before, socket.assigns.cursor)
  rows = Audit.list_entries(filters, @limit)

  socket =
    Enum.reduce(rows, socket, fn row, s -> stream_insert(s, :entries, row, at: -1) end)

  {:noreply,
   socket
   |> assign(:cursor, cursor_from(rows) || socket.assigns.cursor)
   |> assign(:has_more?, length(rows) == @limit)}
end

defp cursor_from([]), do: nil
defp cursor_from(rows), do: (rows |> List.last() |> then(&{&1.inserted_at, &1.id}))
```

Add `<Components.viewport_sentinel has_more?={@has_more?} />` inside `render/1`, immediately after the audit table.

- [ ] **Step 5: Run, expect pass**

```bash
mix test test/user_flows/audit_log_test.exs
```

- [ ] **Step 6: Format + commit**

```bash
mix format lib/web/live/audit_log_live/index.ex lib/web/live/audit_log_live/components.ex test/user_flows/audit_log_test.exs
git add lib/web/live/audit_log_live/index.ex lib/web/live/audit_log_live/components.ex test/user_flows/audit_log_test.exs
git commit -m "Add cursor pagination and load-more sentinel to audit-log index"
```

---

### Task 2.5: Inline expand on row click

**Files:**
- Modify: `test/user_flows/audit_log_test.exs`

This is mostly already done in 2.2 — the row click handler exists and the expanded panel is in the components module. We just need the E2E coverage.

- [ ] **Step 1: Write failing E2E test**

Append to `test/user_flows/audit_log_test.exs`:

```elixir
test "clicking a row expands its full payload", %{conn: conn, row_a: a} do
  conn
  |> log_in_e2e(role: :admin)
  |> visit(~p"/admin/audit-log")
  |> click(test_id("audit-row-#{a.id}"))
  |> wait_liveview()
  |> assert_has("*", text: a.command_id)
  |> assert_has("*", text: a.correlation_id)
end
```

- [ ] **Step 2: Run, expect pass (or trivially adjust)**

```bash
mix test test/user_flows/audit_log_test.exs
```

If `click(test_id("audit-row-#{a.id}"))` matches the outer wrapper instead of the inner `<button>`, switch the row container to a `<div>` and the inner element to a `<button>` with the test id. Adjust until the click hits the right target.

- [ ] **Step 3: Format + commit**

```bash
mix format test/user_flows/audit_log_test.exs
git add test/user_flows/audit_log_test.exs
git commit -m "E2E coverage for inline-expand on audit rows"
```

---

### Task 2.6: Real-time prepend via PubSub

**Files:**
- Modify: `lib/web/live/audit_log_live/index.ex`
- Modify: `test/user_flows/audit_log_test.exs` (or use a LiveView test instead — see below)

The E2E suite uses Playwright in a separate browser process. Triggering a real `Bus.dispatch` while the playwright session is alive risks timing flakes. **Use a LiveView test** for this case, not E2E.

**Files:**
- Create: `test/web/live/audit_log_live_test.exs`

- [ ] **Step 1: Write failing LiveView test**

Create `test/web/live/audit_log_live_test.exs`:

```elixir
defmodule Web.AuditLogLive.IndexTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Ancestry.Factory

  setup do
    admin = insert(:account, role: :admin)
    %{conn: log_in_account(build_conn(), admin), admin: admin}
  end

  test "prepends new row when {:audit_logged, row} arrives", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin/audit-log")

    new_row =
      build(:audit_log,
        id: 999_999,
        account_email: "live@example.com",
        command_module: "Ancestry.Commands.AddCommentToPhoto",
        inserted_at: NaiveDateTime.utc_now()
      )

    send(view.pid, {:audit_logged, new_row})

    assert render(view) =~ "live@example.com"
  end

  test "discards row that doesn't match active organization filter", %{conn: conn} do
    org = insert(:organization)
    {:ok, view, _html} = live(conn, ~p"/admin/audit-log?organization_id=#{org.id}")

    other_org_row =
      build(:audit_log, id: 999_998, organization_id: org.id + 1, account_email: "other@x.com")

    send(view.pid, {:audit_logged, other_org_row})

    refute render(view) =~ "other@x.com"
  end
end
```

If `log_in_account/2` isn't exposed by `Web.ConnCase`, use whatever helper the existing LiveView tests use to authenticate.

- [ ] **Step 2: Run, expect failure**

```bash
mix test test/web/live/audit_log_live_test.exs
```

- [ ] **Step 3: Subscribe + handle_info in `Index`**

Update `lib/web/live/audit_log_live/index.ex`:

```elixir
@impl true
def mount(_params, _session, socket) do
  if connected?(socket), do: Phoenix.PubSub.subscribe(Ancestry.PubSub, "audit_log")

  {:ok,
   socket
   |> assign(:page_title, gettext("Audit log"))
   |> assign(:expanded_id, nil)
   |> assign(:filters, %{})
   |> assign(:cursor, nil)
   |> assign(:has_more?, false)
   |> assign(:organizations, Ancestry.Organizations.list_organizations())
   |> assign(:accounts, Audit.list_audit_accounts(%{}))
   |> stream(:entries, [])}
end

@impl true
def handle_info({:audit_logged, row}, socket) do
  if matches_filters?(row, socket.assigns.filters) do
    {:noreply, stream_insert(socket, :entries, row, at: 0)}
  else
    {:noreply, socket}
  end
end

defp matches_filters?(row, filters) do
  Enum.all?(filters, fn
    {:organization_id, id} -> row.organization_id == id
    {:account_id, id} -> row.account_id == id
    {:before, _} -> true
  end)
end
```

Note `connected?(socket)` — only subscribe in the live process, not the static render pass.

- [ ] **Step 4: Run, expect pass**

```bash
mix test test/web/live/audit_log_live_test.exs
```

- [ ] **Step 5: Format + commit**

```bash
mix format lib/web/live/audit_log_live/index.ex test/web/live/audit_log_live_test.exs
git add lib/web/live/audit_log_live/index.ex test/web/live/audit_log_live_test.exs
git commit -m "Subscribe Index to audit_log topic and prepend new rows live"
```

---

## Phase 3 — Org-scoped page

Goal: `/org/:org_id/audit-log` shows only that org's rows, with the same UI minus the organization filter.

---

### Task 3.1: `/org/:org_id/audit-log` route + `OrgIndex` LiveView

**Files:**
- Create: `lib/web/live/audit_log_live/org_index.ex`
- Modify: `lib/web/router.ex`
- Modify: `test/user_flows/audit_log_test.exs`

- [ ] **Step 1: Add the route**

In `lib/web/router.ex`, inside the `live_session :organization` block, add:

```elixir
live "/audit-log", AuditLogLive.OrgIndex, :index
```

(The route already lives under the `scope "/org/:org_id"` prefix, so the full path is `/org/:org_id/audit-log`.)

- [ ] **Step 2: Write failing E2E tests**

Append to `test/user_flows/audit_log_test.exs`:

```elixir
test "org-scoped page only shows that org's rows", %{conn: conn, org_a: org_a, row_a: a, row_b: b} do
  conn
  |> log_in_e2e(role: :admin)
  |> visit(~p"/org/#{org_a.id}/audit-log")
  |> assert_has(test_id("audit-row-#{a.id}"))
  |> refute_has(test_id("audit-row-#{b.id}"))
end

test "org-scoped page hides the organization filter", %{conn: conn, org_a: org_a} do
  conn
  |> log_in_e2e(role: :admin)
  |> visit(~p"/org/#{org_a.id}/audit-log")
  |> refute_has(test_id("audit-filter-org"))
  |> assert_has(test_id("audit-filter-account"))
end

test "editor cannot access org-scoped audit log", %{conn: conn, org_a: org_a} do
  conn
  |> log_in_e2e(role: :editor, organization_ids: [org_a.id])
  |> visit(~p"/org/#{org_a.id}/audit-log")
  |> assert_path("/org")
end
```

- [ ] **Step 3: Run, expect failure**

- [ ] **Step 4: Implement `OrgIndex`**

Create `lib/web/live/audit_log_live/org_index.ex`:

```elixir
defmodule Web.AuditLogLive.OrgIndex do
  use Web, :live_view

  use Permit.Phoenix.LiveView,
    authorization_module: Ancestry.Authorization,
    resource_module: Ancestry.Audit.Log,
    scope_subject: &Function.identity/1,
    skip_preload: [:index]

  alias Ancestry.Audit
  alias Web.AuditLogLive.Components

  @limit 50

  @impl true
  def handle_unauthorized(_action, socket) do
    {:halt,
     socket
     |> put_flash(:error, gettext("You don't have permission to access this page"))
     |> push_navigate(to: ~p"/org")}
  end

  @impl true
  def mount(_params, _session, socket) do
    org_id = socket.assigns.current_scope.organization.id
    if connected?(socket), do: Phoenix.PubSub.subscribe(Ancestry.PubSub, "audit_log:org:#{org_id}")

    {:ok,
     socket
     |> assign(:page_title, gettext("Audit log"))
     |> assign(:expanded_id, nil)
     |> assign(:filters, %{organization_id: org_id})
     |> assign(:cursor, nil)
     |> assign(:has_more?, false)
     |> assign(:accounts, Audit.list_audit_accounts(%{organization_id: org_id}))
     |> stream(:entries, [])}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    org_id = socket.assigns.current_scope.organization.id

    filters =
      %{organization_id: org_id}
      |> maybe_put(:account_id, parse_int(params["account_id"]))

    rows = Audit.list_entries(filters, @limit)

    {:noreply,
     socket
     |> assign(:filters, filters)
     |> assign(:cursor, cursor_from(rows))
     |> assign(:has_more?, length(rows) == @limit)
     |> stream(:entries, rows, reset: true)}
  end

  @impl true
  def handle_event("filter", %{"filters" => params}, socket) do
    org_id = socket.assigns.current_scope.organization.id

    query =
      params
      |> Map.take(["account_id"])
      |> Enum.reject(fn {_, v} -> v in [nil, ""] end)
      |> URI.encode_query()

    path =
      if query == "",
        do: ~p"/org/#{org_id}/audit-log",
        else: ~p"/org/#{org_id}/audit-log?#{query}"

    {:noreply, push_patch(socket, to: path)}
  end

  @impl true
  def handle_event("load_more", _, socket) do
    filters = Map.put(socket.assigns.filters, :before, socket.assigns.cursor)
    rows = Audit.list_entries(filters, @limit)

    socket =
      Enum.reduce(rows, socket, fn row, s -> stream_insert(s, :entries, row, at: -1) end)

    {:noreply,
     socket
     |> assign(:cursor, cursor_from(rows) || socket.assigns.cursor)
     |> assign(:has_more?, length(rows) == @limit)}
  end

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    id = String.to_integer(id)
    next = if socket.assigns.expanded_id == id, do: nil, else: id
    {:noreply, assign(socket, :expanded_id, next)}
  end

  @impl true
  def handle_info({:audit_logged, row}, socket) do
    if matches_filters?(row, socket.assigns.filters) do
      {:noreply, stream_insert(socket, :entries, row, at: 0)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
        <h1 class="font-cm-display text-cm-indigo text-lg uppercase pb-4">
          {gettext("Audit log")}
        </h1>
        <Components.filter_bar
          organizations={[]}
          accounts={@accounts}
          filters={@filters}
          show_organization?={false}
        />
        <Components.audit_table stream={@streams.entries} expanded_id={@expanded_id} />
        <Components.viewport_sentinel has_more?={@has_more?} />
      </div>
    </Layouts.app>
    """
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)

  defp parse_int(nil), do: nil
  defp parse_int(""), do: nil
  defp parse_int(s) when is_binary(s), do: String.to_integer(s)

  defp cursor_from([]), do: nil
  defp cursor_from(rows), do: (rows |> List.last() |> then(&{&1.inserted_at, &1.id}))

  defp matches_filters?(row, filters) do
    Enum.all?(filters, fn
      {:organization_id, id} -> row.organization_id == id
      {:account_id, id} -> row.account_id == id
      {:before, _} -> true
    end)
  end
end
```

There is significant duplication between `Index` and `OrgIndex` (cursor helpers, parse_int, matches_filters?, load_more, toggle). Leave the duplication in for this task. Task 3.2 extracts shared helpers as its own commit so the diff is focused and reviewable.

- [ ] **Step 5: Run, expect pass**

```bash
mix test test/user_flows/audit_log_test.exs
```

- [ ] **Step 6: Format + commit**

```bash
mix format lib/web/router.ex lib/web/live/audit_log_live/org_index.ex test/user_flows/audit_log_test.exs
git add lib/web/router.ex lib/web/live/audit_log_live/org_index.ex test/user_flows/audit_log_test.exs
git commit -m "Add /org/:org_id/audit-log scoped to a single organization"
```

---

### Task 3.2: Extract shared helpers between Index and OrgIndex

**Files:**
- Create: `lib/web/live/audit_log_live/shared.ex`
- Modify: `lib/web/live/audit_log_live/index.ex`
- Modify: `lib/web/live/audit_log_live/org_index.ex`

This is a pure refactor — no behavior change, no new tests. It exists as its own commit so the OrgIndex commit stays focused on the new feature.

- [ ] **Step 1: Create the shared module**

Create `lib/web/live/audit_log_live/shared.ex`:

```elixir
defmodule Web.AuditLogLive.Shared do
  @moduledoc "Helpers shared between AuditLogLive.Index and AuditLogLive.OrgIndex."

  def parse_int(nil), do: nil
  def parse_int(""), do: nil
  def parse_int(s) when is_binary(s), do: String.to_integer(s)

  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, key, val), do: Map.put(map, key, val)

  def cursor_from([]), do: nil
  def cursor_from(rows), do: rows |> List.last() |> then(&{&1.inserted_at, &1.id})

  def matches_filters?(row, filters) do
    Enum.all?(filters, fn
      {:organization_id, id} -> row.organization_id == id
      {:account_id, id} -> row.account_id == id
      {:before, _} -> true
    end)
  end
end
```

- [ ] **Step 2: Replace local copies with calls**

In both `lib/web/live/audit_log_live/index.ex` and `lib/web/live/audit_log_live/org_index.ex`:
- Remove the private `parse_int/1`, `maybe_put/3`, `cursor_from/1`, `matches_filters?/2` definitions.
- Add `alias Web.AuditLogLive.Shared` near the existing aliases.
- Replace inline calls with `Shared.parse_int(...)`, `Shared.maybe_put(...)`, etc.

- [ ] **Step 3: Run all audit-log tests, expect pass**

```bash
mix test test/user_flows/audit_log_test.exs test/web/live/audit_log_live_test.exs test/ancestry/audit_test.exs
```

- [ ] **Step 4: Format + commit**

```bash
mix format lib/web/live/audit_log_live/
git add lib/web/live/audit_log_live/
git commit -m "Extract audit-log LiveView helpers into Web.AuditLogLive.Shared"
```

---

## Phase 4 — Detail page

Goal: `/admin/audit-log/:id` shows the full record and every entry sharing its `correlation_id`.

---

### Task 4.1: `Show` LiveView with correlated rows

**Files:**
- Create: `lib/web/live/audit_log_live/show.ex`
- Modify: `lib/web/router.ex`
- Modify: `test/user_flows/audit_log_test.exs`

- [ ] **Step 1: Add the route**

In `lib/web/router.ex` inside `live_session :admin`:

```elixir
live "/admin/audit-log/:id", AuditLogLive.Show, :show
```

- [ ] **Step 2: Write failing E2E tests**

Append to `test/user_flows/audit_log_test.exs`:

```elixir
test "detail page shows full record and correlated rows", %{conn: conn} do
  cid = "req-#{Ecto.UUID.generate()}"
  a = insert(:audit_log, correlation_id: cid, inserted_at: ~N[2026-05-09 10:00:00])
  b = insert(:audit_log, correlation_id: cid, inserted_at: ~N[2026-05-09 10:00:01])

  conn
  |> log_in_e2e(role: :admin)
  |> visit(~p"/admin/audit-log/#{a.id}")
  |> assert_has("*", text: a.command_id)
  |> assert_has("*", text: cid)
  |> assert_has(test_id("related-event-#{b.id}"))
end

test "detail page shows 'No related events' when alone", %{conn: conn} do
  cid = "req-solo-#{Ecto.UUID.generate()}"
  row = insert(:audit_log, correlation_id: cid)

  conn
  |> log_in_e2e(role: :admin)
  |> visit(~p"/admin/audit-log/#{row.id}")
  |> assert_has("*", text: "No related events")
end
```

- [ ] **Step 3: Run, expect failure**

- [ ] **Step 4: Implement `Show`**

Create `lib/web/live/audit_log_live/show.ex`:

```elixir
defmodule Web.AuditLogLive.Show do
  use Web, :live_view

  use Permit.Phoenix.LiveView,
    authorization_module: Ancestry.Authorization,
    resource_module: Ancestry.Audit.Log,
    scope_subject: &Function.identity/1,
    skip_preload: [:show]

  alias Ancestry.Audit

  @impl true
  def handle_unauthorized(_action, socket) do
    {:halt,
     socket
     |> put_flash(:error, gettext("You don't have permission to access this page"))
     |> push_navigate(to: ~p"/org")}
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    entry = Audit.get_entry!(id)
    related = entry.correlation_id |> Audit.list_correlated_entries() |> Enum.reject(&(&1.id == entry.id))

    {:ok,
     socket
     |> assign(:page_title, gettext("Audit entry"))
     |> assign(:entry, entry)
     |> assign(:related, related)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 py-6 space-y-6">
        <h1 class="font-cm-display text-cm-indigo text-lg uppercase">
          {gettext("Audit entry")}
        </h1>

        <dl class="grid grid-cols-3 gap-2 font-cm-mono text-[11px]">
          <dt class="font-bold uppercase">{gettext("Timestamp")}</dt>
          <dd class="col-span-2">{Calendar.strftime(@entry.inserted_at, "%Y-%m-%d %H:%M:%S")}</dd>
          <dt class="font-bold uppercase">{gettext("Account")}</dt>
          <dd class="col-span-2">{@entry.account_email}</dd>
          <dt class="font-bold uppercase">{gettext("Organization")}</dt>
          <dd class="col-span-2">{@entry.organization_name || "—"}</dd>
          <dt class="font-bold uppercase">{gettext("Command")}</dt>
          <dd class="col-span-2">{@entry.command_module}</dd>
          <dt class="font-bold uppercase">command_id</dt>
          <dd class="col-span-2">{@entry.command_id}</dd>
          <dt class="font-bold uppercase">correlation_id</dt>
          <dd class="col-span-2">{@entry.correlation_id}</dd>
          <dt class="font-bold uppercase">{gettext("Payload")}</dt>
          <dd class="col-span-2">
            <pre class="whitespace-pre-wrap break-all">{Jason.encode!(@entry.payload, pretty: true)}</pre>
          </dd>
        </dl>

        <section>
          <h2 class="font-cm-display text-cm-indigo text-base uppercase pb-2">
            {gettext("Related events")}
          </h2>
          <p :if={@related == []}>{gettext("No related events")}</p>
          <ul :if={@related != []} class="space-y-2 font-cm-mono text-[11px]">
            <li :for={r <- @related} {test_id("related-event-#{r.id}")}>
              <.link navigate={~p"/admin/audit-log/#{r.id}"} class="underline text-cm-coral">
                {Calendar.strftime(r.inserted_at, "%Y-%m-%d %H:%M:%S")} — {short(r.command_module)}
              </.link>
            </li>
          </ul>
        </section>
      </div>
    </Layouts.app>
    """
  end

  defp short(mod), do: mod |> String.split(".") |> List.last()
end
```

Add `Audit.get_entry!/1` to `lib/ancestry/audit.ex`:

```elixir
def get_entry!(id), do: Repo.get!(Log, id)
```

(This is a one-line addition; piggyback it into this same task's commit. Add a one-line unit test alongside.)

- [ ] **Step 5: Run, expect pass**

```bash
mix test test/user_flows/audit_log_test.exs test/ancestry/audit_test.exs
```

- [ ] **Step 6: Format + commit**

```bash
mix format lib/web/router.ex lib/web/live/audit_log_live/show.ex lib/ancestry/audit.ex test/user_flows/audit_log_test.exs test/ancestry/audit_test.exs
git add lib/web/router.ex lib/web/live/audit_log_live/show.ex lib/ancestry/audit.ex test/user_flows/audit_log_test.exs test/ancestry/audit_test.exs
git commit -m "Add /admin/audit-log/:id detail page with correlated events"
```

---

## Phase 5 — Navigation

Goal: super-admins see "Audit log" links in the nav drawer in both contexts.

---

### Task 5.1: Add nav drawer entries

**Files:**
- Modify: `lib/web/components/nav_drawer.ex`
- Modify: `test/user_flows/audit_log_test.exs`

- [ ] **Step 1: Write failing E2E test**

Append to `test/user_flows/audit_log_test.exs`:

```elixir
test "nav drawer shows audit-log link to admin", %{conn: conn, org_a: org_a} do
  conn
  |> log_in_e2e(role: :admin, organization_ids: [org_a.id])
  |> visit(~p"/org/#{org_a.id}")
  |> click(test_id("hamburger-menu"))
  |> assert_has(test_id("nav-audit-log-org"))

  conn
  |> log_in_e2e(role: :admin)
  |> visit(~p"/admin/accounts")
  |> click(test_id("hamburger-menu"))
  |> assert_has(test_id("nav-audit-log-admin"))
end

test "nav drawer hides audit-log link from editor", %{conn: conn, org_a: org_a} do
  conn
  |> log_in_e2e(role: :editor, organization_ids: [org_a.id])
  |> visit(~p"/org/#{org_a.id}")
  |> click(test_id("hamburger-menu"))
  |> refute_has(test_id("nav-audit-log-org"))
end
```

- [ ] **Step 2: Run, expect failure**

- [ ] **Step 3: Add the links**

In `lib/web/components/nav_drawer.ex`, near the existing `nav-accounts` link, add the top-level audit log link inside the same `if can?` block (split into two siblings if both should be visible):

```heex
<%= if can?(@current_scope, :index, Ancestry.Audit.Log) do %>
  <.link
    {test_id("nav-audit-log-admin")}
    href="/admin/audit-log"
    class={[
      "flex items-center w-full px-4 py-3 text-left rounded-cm min-h-[44px]",
      "font-cm-mono text-[11px] font-bold uppercase tracking-wider",
      "transition-colors text-cm-black hover:bg-cm-surface"
    ]}
  >
    {gettext("Audit log")}
  </.link>
<% end %>
```

For the org-scoped link, add another `if can?(...) and current_scope.organization` block somewhere appropriate (probably near the org-context links — locate them with `grep -n "current_scope.organization" lib/web/components/nav_drawer.ex`):

```heex
<%= if @current_scope && @current_scope.organization && can?(@current_scope, :index, Ancestry.Audit.Log) do %>
  <.link
    {test_id("nav-audit-log-org")}
    href={"/org/#{@current_scope.organization.id}/audit-log"}
    class={[
      "flex items-center w-full px-4 py-3 text-left rounded-cm min-h-[44px]",
      "font-cm-mono text-[11px] font-bold uppercase tracking-wider",
      "transition-colors text-cm-black hover:bg-cm-surface"
    ]}
  >
    {gettext("Audit log")}
  </.link>
<% end %>
```

If the drawer doesn't currently have an explicit org-context section, place this link near other org-scoped links like "Families" / "People" — search the file for the pattern.

- [ ] **Step 4: Run, expect pass**

```bash
mix test test/user_flows/audit_log_test.exs
```

- [ ] **Step 5: Format + commit**

```bash
mix format lib/web/components/nav_drawer.ex test/user_flows/audit_log_test.exs
git add lib/web/components/nav_drawer.ex test/user_flows/audit_log_test.exs
git commit -m "Surface audit-log links in nav drawer for super-admins"
```

---

## Phase 6 — i18n

Goal: every visible `gettext/1` string has a Spanish translation in `priv/gettext/es-UY/LC_MESSAGES/default.po`.

---

### Task 6.1: Extract and translate

**Files:**
- Modify: `priv/gettext/default.pot`
- Modify: `priv/gettext/es-UY/LC_MESSAGES/default.po`

- [ ] **Step 1: Extract**

```bash
mix gettext.extract --merge
```

- [ ] **Step 2: Inspect the diff**

```bash
git diff priv/gettext/
```

Confirm new entries for: `Audit log`, `Audit entry`, `Organization`, `Account`, `All organizations`, `All accounts`, `Load more`, `Related events`, `No related events`, `Timestamp`, `Command`, `Payload`, `Open`, `You don't have permission to access this page` (if not already translated).

- [ ] **Step 3: Fill Spanish translations**

In `priv/gettext/es-UY/LC_MESSAGES/default.po`, fill in `msgstr` for each new entry. Suggested:

| English | Spanish (es-UY) |
|---|---|
| Audit log | Bitácora de auditoría |
| Audit entry | Entrada de auditoría |
| Organization | Organización |
| Account | Cuenta |
| All organizations | Todas las organizaciones |
| All accounts | Todas las cuentas |
| Load more | Cargar más |
| Related events | Eventos relacionados |
| No related events | Sin eventos relacionados |
| Timestamp | Fecha y hora |
| Command | Comando |
| Payload | Datos |
| Open | Abrir |

- [ ] **Step 4: Verify compile**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 5: Commit**

```bash
git add priv/gettext/
git commit -m "Translate audit-log strings to es-UY"
```

---

## Phase 7 — Final verification

---

### Task 7.1: `mix precommit`

- [ ] **Step 1: Run the full precommit**

```bash
mix precommit
```

If anything fails, fix root causes (do not skip checks). Re-run until clean.

- [ ] **Step 2: Re-run the full suite**

```bash
mix test
```

Expected: green.

- [ ] **Step 3: Final commit, if there were fixups**

```bash
git status
# If any files changed during precommit, commit them now.
git add -A
git commit -m "Final formatting/lint sweep for audit-log feature"
```

- [ ] **Step 4: Branch state check**

```bash
git log --oneline main..HEAD
```

Confirm the commit list reads cleanly: permission rule → query module → query helpers → bus broadcast → routes/skeleton → table → filters → infinite scroll → expand E2E → live updates → org-scoped → detail page → nav drawer → i18n → final.

---

## File map

### Created

- `lib/ancestry/audit.ex` — query-only context.
- `lib/web/live/audit_log_live/index.ex` — `/admin/audit-log`.
- `lib/web/live/audit_log_live/org_index.ex` — `/org/:org_id/audit-log`.
- `lib/web/live/audit_log_live/show.ex` — `/admin/audit-log/:id`.
- `lib/web/live/audit_log_live/components.ex` — `audit_table/1`, `filter_bar/1`, `viewport_sentinel/1`.
- `lib/web/live/audit_log_live/shared.ex` — small helpers (cursor, parse_int, matches_filters?).
- `test/ancestry/audit_test.exs`
- `test/user_flows/audit_log_test.exs`
- `test/web/live/audit_log_live_test.exs`

### Modified

- `lib/ancestry/permissions.ex`
- `lib/ancestry/bus.ex`
- `lib/web/router.ex`
- `lib/web/components/nav_drawer.ex`
- `test/ancestry/permissions_test.exs`
- `test/ancestry/bus_test.exs`
- `test/support/factory.ex` (only if `:audit_log` factory was missing)
- `priv/gettext/default.pot`
- `priv/gettext/es-UY/LC_MESSAGES/default.po`

### No migrations.

All required indexes already exist on `audit_log` (see migration `20260507155719_create_audit_log.exs`).
