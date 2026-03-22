# Create Organization Modal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "New Organization" button to the organizations index toolbar that opens an inline modal for creating organizations.

**Architecture:** Inline modal in `OrganizationLive.Index`, toggled by a boolean assign. Form uses `to_form/2` with the existing `Organizations.change_organization/2` changeset. On success, the new org is streamed into the grid.

**Tech Stack:** Phoenix LiveView, Ecto changesets, Tailwind CSS, PhoenixTest.Playwright (E2E tests)

**Spec:** `docs/superpowers/specs/2026-03-21-create-organization-modal-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `lib/web/live/organization_live/index.ex` | Modify | Add assigns (`@show_create_modal`, `@form`), add event handlers (`new_organization`, `cancel_create`, `validate`, `save`) |
| `lib/web/live/organization_live/index.html.heex` | Modify | Add toolbar button, add modal markup with form |
| `test/user_flows/create_organization_test.exs` | Create | E2E test for the create organization flow |

---

### Task 1: Add LiveView assigns and event handlers

**Files:**
- Modify: `lib/web/live/organization_live/index.ex`

Reference the existing edit modal pattern in `lib/web/live/family_live/show.ex:97-152` for the event handler structure.

- [ ] **Step 1: Add new assigns to `mount/3`**

Add `@show_create_modal` and `@form` assigns. The form is initialized from a fresh `Organization` changeset.

Update `mount/3` from:

```elixir
def mount(_params, _session, socket) do
  {:ok, stream(socket, :organizations, Organizations.list_organizations())}
end
```

To:

```elixir
alias Ancestry.Organizations.Organization

def mount(_params, _session, socket) do
  {:ok,
   socket
   |> stream(:organizations, Organizations.list_organizations())
   |> assign(:show_create_modal, false)
   |> assign(:form, to_form(Organizations.change_organization(%Organization{})))}
end
```

Add the `alias` for `Organization` below the existing `alias Ancestry.Organizations` line.

- [ ] **Step 2: Add `new_organization` event handler**

Opens the modal and resets the form to a fresh state (clears any stale input from a previous open/cancel cycle). Add `@impl true` before the first `handle_event` clause (the module already uses `@impl true` on `mount` and `handle_params`, so omitting it on `handle_event` would trigger a compiler warning under `--warnings-as-errors`):

```elixir
@impl true
def handle_event("new_organization", _, socket) do
  {:noreply,
   socket
   |> assign(:show_create_modal, true)
   |> assign(:form, to_form(Organizations.change_organization(%Organization{})))}
end
```

- [ ] **Step 3: Add `cancel_create` event handler**

Closes the modal and resets the form:

```elixir
def handle_event("cancel_create", _, socket) do
  {:noreply,
   socket
   |> assign(:show_create_modal, false)
   |> assign(:form, to_form(Organizations.change_organization(%Organization{})))}
end
```

- [ ] **Step 4: Add `validate` event handler**

Validates the form on change and updates `@form` with errors:

```elixir
def handle_event("validate", %{"organization" => params}, socket) do
  changeset =
    %Organization{}
    |> Organizations.change_organization(params)
    |> Map.put(:action, :validate)

  {:noreply, assign(socket, :form, to_form(changeset))}
end
```

- [ ] **Step 5: Add `save` event handler**

Creates the organization. On success: streams it into the grid, closes modal, sets flash. On error: updates form with errors.

```elixir
def handle_event("save", %{"organization" => params}, socket) do
  case Organizations.create_organization(params) do
    {:ok, organization} ->
      {:noreply,
       socket
       |> stream_insert(:organizations, organization)
       |> assign(:show_create_modal, false)
       |> assign(:form, to_form(Organizations.change_organization(%Organization{})))
       |> put_flash(:info, "Organization created")}

    {:error, changeset} ->
      {:noreply, assign(socket, :form, to_form(changeset))}
  end
end
```

- [ ] **Step 6: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles with no warnings or errors.

- [ ] **Step 7: Commit**

```bash
git add lib/web/live/organization_live/index.ex
git commit -m "Add event handlers for create organization modal"
```

---

### Task 2: Add toolbar button and modal to template

**Files:**
- Modify: `lib/web/live/organization_live/index.html.heex`

Reference the existing patterns:
- Toolbar button: `lib/web/live/family_live/index.html.heex` (the "New Family" link in the toolbar)
- Modal with form: `lib/web/live/family_live/show.html.heex:142-153` (the edit family modal)
- Delete confirmation modal: `lib/web/live/family_live/show.html.heex` (for overlay/backdrop structure)

- [ ] **Step 1: Add "New Organization" button to the toolbar**

Update the toolbar from:

```heex
<:toolbar>
  <div class="max-w-7xl mx-auto flex items-center justify-between py-3 px-4 sm:px-6 lg:px-8">
    <h1 class="text-lg font-semibold text-base-content">Organizations</h1>
  </div>
</:toolbar>
```

To:

```heex
<:toolbar>
  <div class="max-w-7xl mx-auto flex items-center justify-between py-3 px-4 sm:px-6 lg:px-8">
    <h1 class="text-lg font-semibold text-base-content">Organizations</h1>
    <button
      phx-click="new_organization"
      class="inline-flex items-center gap-2 rounded-lg bg-primary px-4 py-2.5 text-sm font-semibold text-primary-content shadow-sm hover:bg-primary/90 transition-colors"
      {test_id("org-new-btn")}
    >
      <.icon name="hero-plus" class="w-4 h-4" /> New Organization
    </button>
  </div>
</:toolbar>
```

- [ ] **Step 2: Add the modal markup after the outer container**

Add the modal **after** the closing `</div>` of the `max-w-7xl` outer container div and **before** `</Layouts.app>`. This matches the existing pattern in `FamilyLive.Show` where modals are siblings of the main content, not children. Also add a `test_id` to the backdrop element for reliable test targeting:

```heex
<%= if @show_create_modal do %>
  <div class="fixed inset-0 z-50 flex items-center justify-center">
    <div
      class="absolute inset-0 bg-black/60 backdrop-blur-sm"
      phx-click="cancel_create"
      {test_id("org-create-backdrop")}
    >
    </div>
    <div
      id="create-organization-modal"
      class="relative card bg-base-100 shadow-2xl w-full max-w-md mx-4 p-8"
      {test_id("org-create-modal")}
    >
      <h2 class="text-xl font-bold text-base-content mb-6">New Organization</h2>
      <.form
        for={@form}
        id="create-organization-form"
        phx-change="validate"
        phx-submit="save"
        {test_id("org-create-form")}
      >
        <.input field={@form[:name]} label="Organization name" autofocus />
        <div class="flex gap-3 mt-6">
          <button
            type="submit"
            class="btn btn-primary flex-1"
            phx-disable-with="Creating..."
            {test_id("org-create-submit-btn")}
          >
            Create
          </button>
          <button type="button" phx-click="cancel_create" class="btn btn-ghost flex-1">
            Cancel
          </button>
        </div>
      </.form>
    </div>
  </div>
<% end %>
```

- [ ] **Step 3: Verify it works manually**

Run: `iex -S mix phx.server`

Visit `http://localhost:4000`. Verify:
1. "New Organization" button appears in the toolbar
2. Clicking it opens the modal
3. Typing a name and clicking "Create" creates the org and closes the modal
4. The new org appears in the grid
5. Flash message "Organization created" shows
6. Clicking backdrop or Cancel closes the modal without creating

- [ ] **Step 4: Commit**

```bash
git add lib/web/live/organization_live/index.html.heex
git commit -m "Add create organization toolbar button and modal template"
```

---

### Task 3: Write E2E tests

**Files:**
- Create: `test/user_flows/create_organization_test.exs`

Reference the existing E2E test pattern in `test/user_flows/create_family_test.exs` for structure, imports, and assertion style. Uses `Web.E2ECase` with `PhoenixTest.Playwright`.

- [ ] **Step 1: Create the test file**

```elixir
defmodule Web.UserFlows.CreateOrganizationTest do
  use Web.E2ECase

  # Given a system with an existing organization
  # When the user visits the organizations index page and clicks "New Organization"
  # Then the create modal appears
  #
  # When the user submits the form without a name
  # Then validation errors are shown
  #
  # When the user enters a name and submits
  # Then the modal closes and the new organization appears in the grid
  #
  # When the user clicks the backdrop
  # Then the modal closes without creating anything
  #
  # When the user clicks the Cancel button
  # Then the modal closes without creating anything
  #
  # When the user opens the modal, types a partial name, cancels, then reopens
  # Then the form is empty (no stale input or errors)
  setup do
    org = insert(:organization, name: "Existing Org")
    %{org: org}
  end

  test "create organization via modal", %{conn: conn, org: _org} do
    # Visit the organizations index page
    conn =
      conn
      |> visit(~p"/")
      |> wait_liveview()
      |> assert_has(test_id("org-new-btn"))

    # Click "New Organization" — modal should appear
    conn =
      conn
      |> click(test_id("org-new-btn"))
      |> assert_has(test_id("org-create-modal"))
      |> assert_has(test_id("org-create-form"))

    # Submit without a name — should show validation error
    conn =
      conn
      |> fill_in("Organization name", with: " ")
      |> click_button(test_id("org-create-submit-btn"), "Create")

    conn = assert_has(conn, "p", text: "can't be blank")

    # Fill in a valid name and submit
    conn =
      conn
      |> fill_in("Organization name", with: "New Test Org")
      |> click_button(test_id("org-create-submit-btn"), "Create")
      |> wait_liveview()

    # Modal should close and the new org should appear in the grid
    conn =
      conn
      |> refute_has(test_id("org-create-modal"))
      |> assert_has("h2", text: "New Test Org")

    # Verify flash message
    conn = assert_has(conn, text: "Organization created")

    # Verify the existing org is still there
    assert_has(conn, "h2", text: "Existing Org")
  end

  test "dismiss modal via backdrop click", %{conn: conn} do
    conn =
      conn
      |> visit(~p"/")
      |> wait_liveview()
      |> click(test_id("org-new-btn"))
      |> assert_has(test_id("org-create-modal"))

    # Fill in a name but click the backdrop to dismiss
    conn =
      conn
      |> fill_in("Organization name", with: "Should Not Be Created")
      |> click(test_id("org-create-backdrop"))
      |> wait_liveview()

    # Modal should close, org should NOT be in the grid
    conn
    |> refute_has(test_id("org-create-modal"))
    |> refute_has("h2", text: "Should Not Be Created")
  end

  test "dismiss modal via cancel button", %{conn: conn} do
    conn =
      conn
      |> visit(~p"/")
      |> wait_liveview()
      |> click(test_id("org-new-btn"))
      |> assert_has(test_id("org-create-modal"))

    # Click cancel
    conn =
      conn
      |> click_button("Cancel")
      |> wait_liveview()

    conn
    |> refute_has(test_id("org-create-modal"))
  end

  test "reopening modal after cancel shows clean form", %{conn: conn} do
    conn =
      conn
      |> visit(~p"/")
      |> wait_liveview()
      |> click(test_id("org-new-btn"))
      |> assert_has(test_id("org-create-modal"))

    # Type something, then cancel
    conn =
      conn
      |> fill_in("Organization name", with: "Partial Name")
      |> click_button("Cancel")
      |> wait_liveview()
      |> refute_has(test_id("org-create-modal"))

    # Reopen — form should be clean
    conn =
      conn
      |> click(test_id("org-new-btn"))
      |> assert_has(test_id("org-create-modal"))

    # The input should be empty (check the value attribute, not text content)
    conn
    |> assert_has("input[name='organization[name]'][value='']")
  end
end
```

- [ ] **Step 2: Run the E2E tests**

Run: `mix test test/user_flows/create_organization_test.exs`
Expected: All 4 tests pass.

- [ ] **Step 3: Commit**

```bash
git add test/user_flows/create_organization_test.exs
git commit -m "Add E2E tests for create organization modal"
```

---

### Task 4: Run precommit checks

- [ ] **Step 1: Run `mix precommit`**

Run: `mix precommit`
Expected: Compilation (warnings-as-errors), formatting, and all tests pass.

- [ ] **Step 2: Fix any issues**

If any check fails, fix the issue and re-run `mix precommit`.

- [ ] **Step 3: Final commit if formatting changed**

```bash
git add -A
git commit -m "Fix formatting from precommit"
```
