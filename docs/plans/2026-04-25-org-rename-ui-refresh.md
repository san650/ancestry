# Organization Rename + UI Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let admins rename organizations via selection mode, and update org/family index pages to use white backgrounds with a new card shadow token.

**Architecture:** Two independent changes sharing a CSS token. Part 1 adds `shadow-ds-card` and applies it to both index templates. Part 2 adds rename state + event handlers to `OrganizationLive.Index` with an inline modal following the established pattern.

**Tech Stack:** Phoenix LiveView, Tailwind CSS, Permit (authorization), ExMachina (test factories), PhoenixTest E2E

---

### Task 1: Add `shadow-ds-card` CSS token

**Files:**
- Modify: `assets/css/app.css:71-74` (after `shadow-ds-ambient`)

- [ ] **Step 1: Add the shadow utility**

In `assets/css/app.css`, after the existing `.shadow-ds-ambient` block (line 74), add:

```css
.shadow-ds-card {
  box-shadow: 0 1px 3px rgba(11, 28, 48, 0.08), 0 4px 12px rgba(11, 28, 48, 0.04);
}
```

- [ ] **Step 2: Verify assets compile**

Run: `mix assets.build`
Expected: no errors

- [ ] **Step 3: Commit**

```
git add assets/css/app.css
git commit -m "Add shadow-ds-card CSS token for grounded card elevation"
```

---

### Task 2: Update organization index UI (white bg + card shadows)

**Files:**
- Modify: `lib/web/live/organization_live/index.html.heex:58,98`

- [ ] **Step 1: Change page background**

In `lib/web/live/organization_live/index.html.heex` line 58, change:

```heex
<div class="bg-ds-surface-low min-h-screen">
```

to:

```heex
<div class="bg-white min-h-screen">
```

- [ ] **Step 2: Add card shadow**

In the same file, line 98, change the card class list. The first string in the class list:

```elixir
"block bg-ds-surface-card rounded-ds-sharp p-5 hover:bg-ds-surface-highest transition-colors cursor-pointer",
```

to:

```elixir
"block bg-ds-surface-card rounded-ds-sharp shadow-ds-card p-5 hover:bg-ds-surface-highest transition-colors cursor-pointer",
```

- [ ] **Step 3: Verify visually**

Run: `iex -S mix phx.server` and visit `http://localhost:4000/org`
Expected: White background, cards have subtle shadows, hover still works.

- [ ] **Step 4: Commit**

```
git add lib/web/live/organization_live/index.html.heex
git commit -m "Update org index to white background with card shadows"
```

---

### Task 3: Update family index UI (white bg + card shadows)

**Files:**
- Modify: `lib/web/live/family_live/index.html.heex:3,88,129`

- [ ] **Step 1: Change toolbar background**

In `lib/web/live/family_live/index.html.heex` line 3, change:

```heex
<div class="flex items-center justify-between px-4 py-2 bg-ds-surface-low sm:px-6 lg:px-8">
```

to:

```heex
<div class="flex items-center justify-between px-4 py-2 bg-white sm:px-6 lg:px-8">
```

- [ ] **Step 2: Change page background**

In the same file, line 88, change:

```heex
<div class="bg-ds-surface-low min-h-screen">
```

to:

```heex
<div class="bg-white min-h-screen">
```

- [ ] **Step 3: Add card shadow**

In the same file, line 129, change the card class list. The first string:

```elixir
"group relative bg-ds-surface-card rounded-ds-sharp hover:bg-ds-surface-highest transition-colors overflow-hidden cursor-pointer",
```

to:

```elixir
"group relative bg-ds-surface-card rounded-ds-sharp shadow-ds-card hover:bg-ds-surface-highest transition-colors overflow-hidden cursor-pointer",
```

- [ ] **Step 4: Verify visually**

Visit an org's family index page in the browser.
Expected: White background (including toolbar), cards have subtle shadows.

- [ ] **Step 5: Commit**

```
git add lib/web/live/family_live/index.html.heex
git commit -m "Update family index to white background with card shadows"
```

---

### Task 4: Update DESIGN.md and COMPONENTS.jsonl

**Files:**
- Modify: `DESIGN.md:32-33`
- Modify: `COMPONENTS.jsonl` (append)

- [ ] **Step 1: Update DESIGN.md shadow guidance**

In `DESIGN.md`, replace lines 32-33:

```markdown
- Prefer tonal depth over strong shadows. Use soft shadows only for floating layers.
- Use sharp or lightly rounded corners. Avoid large radii.
```

with:

```markdown
- Use `shadow-ds-card` (`0 1px 3px rgba(11,28,48,0.08), 0 4px 12px rgba(11,28,48,0.04)`) for grounded card elevation on index/grid pages with white backgrounds.
- Reserve `shadow-ds-ambient` (`0 8px 32px rgba(11,28,48,0.06)`) for floating layers: modals, popovers, drawers.
- Index and grid pages use a white (`bg-white`) page background. Cards use `bg-ds-surface-card` + `shadow-ds-card`.
- Use sharp or lightly rounded corners. Avoid large radii.
```

- [ ] **Step 2: Append to COMPONENTS.jsonl**

Append this line to `COMPONENTS.jsonl`:

```json
{"component": "index-card-pattern", "description": "Index/grid pages (org index, family index) use bg-white page background with bg-ds-surface-card cards carrying shadow-ds-card for grounded elevation. shadow-ds-ambient is reserved for floating layers (modals, popovers, drawers). Cards retain rounded-ds-sharp, hover:bg-ds-surface-highest, and transition-colors."}
```

- [ ] **Step 3: Commit**

```
git add DESIGN.md COMPONENTS.jsonl
git commit -m "Document white bg + shadow-ds-card as standard index card pattern"
```

---

### Task 5: Add rename state and event handlers to OrganizationLive.Index

**Files:**
- Modify: `lib/web/live/organization_live/index.ex:8-20` (mount), add handlers after line 95

- [ ] **Step 1: Add rename assigns to mount**

In `lib/web/live/organization_live/index.ex`, in the `mount/3` function (lines 8-20), add three new assigns. Change:

```elixir
     |> assign(:show_create_modal, false)
     |> assign(:form, to_form(Organizations.change_organization(%Organization{})))}
```

to:

```elixir
     |> assign(:show_create_modal, false)
     |> assign(:form, to_form(Organizations.change_organization(%Organization{})))
     |> assign(:show_rename_modal, false)
     |> assign(:rename_form, nil)
     |> assign(:rename_org, nil)}
```

- [ ] **Step 2: Add rename_selected handler**

After the `card_clicked` handler (after line 95), add:

```elixir
  def handle_event("rename_selected", _, socket) do
    [org_id] = MapSet.to_list(socket.assigns.selected_ids)
    org = Organizations.get_organization!(org_id)
    changeset = Organizations.change_organization(org)

    {:noreply,
     socket
     |> assign(:selection_mode, false)
     |> assign(:selected_ids, MapSet.new())
     |> assign(:show_rename_modal, true)
     |> assign(:rename_org, org)
     |> assign(:rename_form, to_form(changeset))}
  end
```

- [ ] **Step 3: Add validate_rename handler**

After the `rename_selected` handler, add:

```elixir
  def handle_event("validate_rename", %{"organization" => params}, socket) do
    changeset =
      socket.assigns.rename_org
      |> Organizations.change_organization(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :rename_form, to_form(changeset))}
  end
```

- [ ] **Step 4: Add save_rename handler**

After the `validate_rename` handler, add:

```elixir
  def handle_event("save_rename", %{"organization" => params}, socket) do
    case Organizations.update_organization(socket.assigns.rename_org, params) do
      {:ok, updated_org} ->
        {:noreply,
         socket
         |> stream_insert(:organizations, updated_org)
         |> assign(:show_rename_modal, false)
         |> assign(:rename_form, nil)
         |> assign(:rename_org, nil)
         |> put_flash(:info, gettext("Organization renamed"))}

      {:error, changeset} ->
        {:noreply, assign(socket, :rename_form, to_form(changeset))}
    end
  end
```

- [ ] **Step 5: Add cancel_rename handler**

After the `save_rename` handler, add:

```elixir
  def handle_event("cancel_rename", _, socket) do
    {:noreply,
     socket
     |> assign(:show_rename_modal, false)
     |> assign(:rename_form, nil)
     |> assign(:rename_org, nil)}
  end
```

- [ ] **Step 6: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: compiles cleanly

- [ ] **Step 7: Commit**

```
git add lib/web/live/organization_live/index.ex
git commit -m "Add rename state and event handlers to org index LiveView"
```

---

### Task 6: Add rename button and modal to org index template

**Files:**
- Modify: `lib/web/live/organization_live/index.html.heex:61-79` (selection bar), append modal after line 178

- [ ] **Step 1: Add Rename button to selection bar**

In `lib/web/live/organization_live/index.html.heex`, replace the selection bar content (lines 61-79). The current Delete button is a single button after the count span. Wrap it in a div with the Rename button. Replace:

```heex
          <button
            phx-click="request_batch_delete"
            disabled={MapSet.size(@selected_ids) == 0}
            class="px-3 py-2 text-sm font-ds-body text-ds-error hover:bg-ds-error/10 rounded-ds-sharp transition-colors lg:bg-ds-error lg:text-white lg:hover:opacity-90 disabled:opacity-40 disabled:cursor-not-allowed"
            {test_id("selection-bar-delete-btn")}
          >
            {gettext("Delete")}
          </button>
```

with:

```heex
          <div class="flex items-center gap-2">
            <%= if MapSet.size(@selected_ids) == 1 and can?(@current_scope, :update, Organization) do %>
              <button
                phx-click="rename_selected"
                class="px-3 py-2 text-sm font-ds-body font-semibold text-ds-on-surface bg-ds-surface-high rounded-ds-sharp transition-colors hover:bg-ds-surface-highest lg:bg-ds-surface-high lg:text-ds-on-surface"
                {test_id("selection-bar-rename-btn")}
              >
                {gettext("Rename")}
              </button>
            <% end %>
            <button
              phx-click="request_batch_delete"
              disabled={MapSet.size(@selected_ids) == 0}
              class="px-3 py-2 text-sm font-ds-body text-ds-error hover:bg-ds-error/10 rounded-ds-sharp transition-colors lg:bg-ds-error lg:text-white lg:hover:opacity-90 disabled:opacity-40 disabled:cursor-not-allowed"
              {test_id("selection-bar-delete-btn")}
            >
              {gettext("Delete")}
            </button>
          </div>
```

- [ ] **Step 2: Add rename modal**

After the create modal closing `<% end %>` (line 178), and before the batch delete modal, add:

```heex
  <%!-- Rename Organization Modal --%>
  <%= if @show_rename_modal do %>
    <div
      id="rename-org-overlay"
      class="fixed inset-0 z-50 flex items-end lg:items-center justify-center"
      phx-window-keydown="cancel_rename"
      phx-key="Escape"
      phx-mounted={JS.focus_first()}
    >
      <div
        class="absolute inset-0 bg-black/60 backdrop-blur-sm"
        phx-click="cancel_rename"
        {test_id("org-rename-backdrop")}
      >
      </div>
      <div
        id="rename-organization-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="rename-org-title"
        class="relative bg-ds-surface-card/80 backdrop-blur-[20px] shadow-ds-ambient w-full max-w-none lg:max-w-md mx-0 lg:mx-4 rounded-t-lg lg:rounded-ds-sharp p-8"
        {test_id("org-rename-modal")}
      >
        <h2
          id="rename-org-title"
          class="text-xl font-ds-heading font-bold text-ds-on-surface mb-6"
        >
          {gettext("Rename Organization")}
        </h2>
        <.form
          for={@rename_form}
          id="rename-organization-form"
          phx-change="validate_rename"
          phx-submit="save_rename"
          {test_id("org-rename-form")}
        >
          <.input field={@rename_form[:name]} label={gettext("Organization name")} autofocus />
          <div class="flex gap-3 mt-6">
            <button
              type="submit"
              class="flex-1 bg-gradient-to-b from-ds-primary to-ds-primary-container text-ds-on-primary rounded-ds-sharp py-2.5 text-sm font-ds-body font-semibold tracking-wide hover:opacity-90 transition-opacity"
              phx-disable-with={gettext("Saving...")}
              {test_id("org-rename-submit-btn")}
            >
              {gettext("Save")}
            </button>
            <button
              type="button"
              phx-click="cancel_rename"
              class="flex-1 bg-ds-surface-high text-ds-on-surface rounded-ds-sharp py-2.5 text-sm font-ds-body font-semibold hover:bg-ds-surface-highest transition-colors"
              {test_id("org-rename-cancel-btn")}
            >
              {gettext("Cancel")}
            </button>
          </div>
        </.form>
      </div>
    </div>
  <% end %>
```

- [ ] **Step 3: Verify compilation and visual check**

Run: `mix compile --warnings-as-errors`
Then visit `/org` in the browser, enter selection mode, select one org, verify "Rename" button appears. Click it, verify modal opens with pre-filled name.

- [ ] **Step 4: Commit**

```
git add lib/web/live/organization_live/index.html.heex
git commit -m "Add rename button in selection bar and rename modal to org index"
```

---

### Task 7: Extract and translate gettext strings

**Files:**
- Modify: `priv/gettext/es-UY/LC_MESSAGES/default.po` (auto-updated by extract)

- [ ] **Step 1: Extract gettext strings**

Run: `mix gettext.extract --merge`
Expected: updates `.pot` and `.po` files with new strings

- [ ] **Step 2: Fill in Spanish translations**

In `priv/gettext/es-UY/LC_MESSAGES/default.po`, find and translate the new entries:

- `"Rename"` → `"Renombrar"`
- `"Rename Organization"` → `"Renombrar Organización"`
- `"Organization renamed"` → `"Organización renombrada"`
- `"Saving..."` → `"Guardando..."`

(The strings `"Save"`, `"Cancel"`, `"Organization name"` should already have translations from the create modal.)

- [ ] **Step 3: Verify no fuzzy/untranslated warnings**

Run: `mix compile --warnings-as-errors`
Expected: compiles cleanly

- [ ] **Step 4: Commit**

```
git add priv/gettext/
git commit -m "Add Spanish translations for org rename strings"
```

---

### Task 8: Write E2E tests for org rename

**Files:**
- Create: `test/user_flows/rename_organization_test.exs`

- [ ] **Step 1: Write the test file**

Create `test/user_flows/rename_organization_test.exs`:

```elixir
defmodule Web.UserFlows.RenameOrganizationTest do
  use Web.E2ECase

  # Renaming an organization
  #
  # Given an existing organization
  # When the admin enters selection mode and selects one org
  # Then the selection bar shows "Rename" alongside "Delete"
  #
  # When the admin clicks "Rename"
  # Then selection mode exits and the rename modal opens with the current name
  #
  # When the admin changes the name and clicks "Save"
  # Then the modal closes and the updated name appears in the grid
  #
  # When the admin opens rename modal and clicks "Cancel"
  # Then the modal closes without changes
  #
  # When the admin submits an empty name
  # Then a validation error is shown
  #
  # When multiple orgs are selected
  # Then the "Rename" button is not shown
  #
  # When a non-admin enters selection mode
  # Then the "Rename" button is not shown
  setup do
    org = insert(:organization, name: "Original Name")
    org2 = insert(:organization, name: "Second Org")
    %{org: org, org2: org2}
  end

  test "admin renames organization via selection mode", %{conn: conn, org: org} do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org")
      |> wait_liveview()
      |> click(test_id("org-index-select-btn"))
      |> wait_liveview()
      |> click(test_id("org-card-#{org.id}"))
      |> wait_liveview()

    # Rename button should be visible
    conn = assert_has(conn, test_id("selection-bar-rename-btn"))

    # Click Rename — modal opens, selection mode exits
    conn =
      conn
      |> click(test_id("selection-bar-rename-btn"))
      |> wait_liveview()
      |> assert_has(test_id("org-rename-modal"))

    # Name input should be pre-filled
    conn = assert_has(conn, "input[name='organization[name]']", value: "Original Name")

    # Change name and save
    conn =
      conn
      |> fill_in("Organization name", with: "Updated Name")
      |> click_button(test_id("org-rename-submit-btn"), "Save")
      |> wait_liveview()

    # Modal should close, name should be updated
    conn
    |> refute_has(test_id("org-rename-modal"))
    |> assert_has("h2", text: "Updated Name")
    |> assert_has(".alert", text: "Organization renamed")
  end

  test "cancel rename closes modal without changes", %{conn: conn, org: org} do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org")
      |> wait_liveview()
      |> click(test_id("org-index-select-btn"))
      |> wait_liveview()
      |> click(test_id("org-card-#{org.id}"))
      |> wait_liveview()
      |> click(test_id("selection-bar-rename-btn"))
      |> wait_liveview()
      |> assert_has(test_id("org-rename-modal"))

    # Cancel
    conn =
      conn
      |> click_button("Cancel")
      |> wait_liveview()

    conn
    |> refute_has(test_id("org-rename-modal"))
    |> assert_has("h2", text: "Original Name")
  end

  test "validation error on empty name", %{conn: conn, org: org} do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org")
      |> wait_liveview()
      |> click(test_id("org-index-select-btn"))
      |> wait_liveview()
      |> click(test_id("org-card-#{org.id}"))
      |> wait_liveview()
      |> click(test_id("selection-bar-rename-btn"))
      |> wait_liveview()

    # Clear name and submit
    conn =
      conn
      |> fill_in("Organization name", with: "")
      |> click_button(test_id("org-rename-submit-btn"), "Save")

    assert_has(conn, "p", text: "can't be blank")
  end

  test "rename button hidden when multiple orgs selected", %{conn: conn, org: org, org2: org2} do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org")
      |> wait_liveview()
      |> click(test_id("org-index-select-btn"))
      |> wait_liveview()
      |> click(test_id("org-card-#{org.id}"))
      |> click(test_id("org-card-#{org2.id}"))
      |> wait_liveview()

    refute_has(conn, test_id("selection-bar-rename-btn"))
  end

  test "rename button hidden for non-admin", %{conn: conn, org: org} do
    conn = log_in_e2e(conn, role: :editor, organization_ids: [org.id])

    conn =
      conn
      |> visit(~p"/org")
      |> wait_liveview()
      |> click(test_id("org-index-select-btn"))
      |> wait_liveview()
      |> click(test_id("org-card-#{org.id}"))
      |> wait_liveview()

    refute_has(conn, test_id("selection-bar-rename-btn"))
  end
end
```

- [ ] **Step 2: Run the tests**

Run: `mix test test/user_flows/rename_organization_test.exs`
Expected: all 5 tests pass

- [ ] **Step 3: Run full test suite**

Run: `mix test`
Expected: all tests pass (no regressions from UI changes)

- [ ] **Step 4: Commit**

```
git add test/user_flows/rename_organization_test.exs
git commit -m "Add E2E tests for org rename flow"
```

---

### Task 9: Run precommit and verify

- [ ] **Step 1: Run precommit**

Run: `mix precommit`
Expected: compiles (warnings-as-errors), formats, tests all pass

- [ ] **Step 2: Fix any issues found**

If precommit reports warnings or failures, fix and re-run.

- [ ] **Step 3: Final commit if needed**

Only if precommit required formatting or other fixes.
