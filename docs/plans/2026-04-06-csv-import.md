# CSV Import from Family Show Page — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a meatball overflow menu to the family show toolbar (desktop only) with Manage People, Create Subfamily, and a new "Import from CSV" action that uploads a CSV file and shows import results in a modal.

**Architecture:** Extract a `import_for_family/3` function from the existing `CSV.import/4` that accepts a family struct directly. The LiveView handles file upload via `allow_upload`, calls the import synchronously inside `consume_uploaded_entries`, and displays results in a two-state modal. The meatball menu is a simple dropdown toggled by a boolean assign with `phx-click-away`.

**Tech Stack:** Phoenix LiveView, NimbleCSV (existing), `allow_upload`, Tailwind CSS

**Design spec:** `docs/plans/2026-04-06-csv-import-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/ancestry/import/csv.ex` | Modify | Add `import_for_family/3`, extract shared logic from `import/4` |
| `lib/ancestry/import.ex` | Modify | Add `import_csv_for_family/3` dispatcher |
| `test/ancestry/import/csv_test.exs` | Modify | Add tests for `import_for_family/3` |
| `lib/web/live/family_live/show.ex` | Modify | Add meatball menu assign, import assigns, `allow_upload`, event handlers |
| `lib/web/live/family_live/show.html.heex` | Modify | Meatball dropdown, import modal (upload + results states) |
| `test/user_flows/csv_import_test.exs` | Create | E2E test for the full import flow |
| `test/user_flows/create_subfamily_test.exs` | Modify | Open meatball menu before clicking Create Subfamily |
| `test/user_flows/manage_people_test.exs` | Modify | Open meatball menu before clicking Manage People |
| `test/support/e2e_case.ex` | Modify | Add `.csv` to `mime_for_extension` |
| `test/fixtures/family_echo_sample.csv` | Create | Test fixture for CSV import |

---

### Task 1: Add `import_for_family/3` to the CSV module

**Files:**
- Modify: `lib/ancestry/import/csv.ex:36-58` (add new function, refactor `import/4`)
- Modify: `lib/ancestry/import.ex:28-37` (add new dispatcher)
- Modify: `test/ancestry/import/csv_test.exs` (add tests)

- [ ] **Step 1: Write the failing test for `import_for_family/3`**

Add to `test/ancestry/import/csv_test.exs` a new describe block:

```elixir
describe "import_for_family/3" do
  test "imports people into an existing family" do
    org = insert(:organization)
    family = insert(:family, organization: org)

    rows = [
      csv_row(%{
        "ID" => "P1",
        "Given names" => "Alice",
        "Surname now" => "Smith",
        "Gender" => "Female"
      }),
      csv_row(%{
        "ID" => "P2",
        "Given names" => "Bob",
        "Surname now" => "Smith",
        "Gender" => "Male"
      })
    ]

    path = write_tmp_csv(build_csv(rows))

    assert {:ok, summary} = CSV.import_for_family(FamilyEcho, family, path)
    assert summary.family.id == family.id
    assert summary.people_created == 2
    assert summary.people_skipped == 0
  end

  test "returns error for missing file" do
    org = insert(:organization)
    family = insert(:family, organization: org)

    assert {:error, "File not found:" <> _} =
             CSV.import_for_family(FamilyEcho, family, "/nonexistent.csv")
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mix test test/ancestry/import/csv_test.exs --seed 0`
Expected: Compilation error — `import_for_family/3` is undefined.

- [ ] **Step 3: Implement `import_for_family/3`**

In `lib/ancestry/import/csv.ex`, extract the shared logic and add the new function:

```elixir
@doc """
Import people and relationships from a CSV file into an existing family.

Unlike `import/4`, this accepts a family struct directly — no name-based lookup.
Returns `{:ok, summary}` on success or `{:error, reason}` on failure.
"""
def import_for_family(adapter_module, %Ancestry.Families.Family{} = family, csv_path) do
  with :ok <- validate_file(csv_path),
       {:ok, rows} <- parse_csv(csv_path) do
    people_result = import_people(adapter_module, family, rows)
    relationships_result = import_relationships(adapter_module, rows)

    {:ok, build_summary(family, people_result, relationships_result)}
  end
end
```

Refactor `import/4` to reuse the shared summary builder:

```elixir
def import(adapter_module, family_name, csv_path, org) do
  with :ok <- validate_file(csv_path),
       {:ok, family} <- find_or_create_family(family_name, org),
       {:ok, rows} <- parse_csv(csv_path) do
    people_result = import_people(adapter_module, family, rows)
    relationships_result = import_relationships(adapter_module, rows)

    {:ok, build_summary(family, people_result, relationships_result)}
  end
end

defp build_summary(family, people_result, relationships_result) do
  %{
    family: family,
    people_created: people_result.created,
    people_updated: people_result.updated,
    people_unchanged: people_result.unchanged,
    people_skipped: people_result.skipped,
    people_errors: people_result.errors,
    people_unchanged_names: people_result.unchanged_names,
    people_updated_names: people_result.updated_names,
    relationships_created: relationships_result.created,
    relationships_duplicates: relationships_result.duplicates,
    relationships_errors: relationships_result.errors
  }
end
```

- [ ] **Step 4: Add the dispatcher to `lib/ancestry/import.ex`**

```elixir
@doc """
Import people and relationships from a CSV file into an existing family.

Like `import_from_csv/4` but accepts a family struct directly.
"""
def import_csv_for_family(adapter_name, family, csv_path) do
  case Map.fetch(@adapters, adapter_name) do
    {:ok, adapter_module} ->
      CSV.import_for_family(adapter_module, family, csv_path)

    :error ->
      available = @adapters |> Map.keys() |> Enum.join(", ")
      {:error, "Unknown adapter: #{adapter_name}. Available: #{available}"}
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/ancestry/import/csv_test.exs --seed 0`
Expected: All tests pass including the new ones. Existing tests remain green (no regression).

- [ ] **Step 6: Commit**

```bash
git add lib/ancestry/import.ex lib/ancestry/import/csv.ex test/ancestry/import/csv_test.exs
git commit -m "Add import_for_family/3 to accept family struct directly"
```

---

### Task 2: Add meatball menu to the family show toolbar

**Files:**
- Modify: `lib/web/live/family_live/show.ex:29-55` (add `:show_menu` assign)
- Modify: `lib/web/live/family_live/show.html.heex:32-91` (replace toolbar buttons with meatball dropdown)

- [ ] **Step 1: Add `:show_menu` assign to mount**

In `lib/web/live/family_live/show.ex`, add to the mount assigns:

```elixir
|> assign(:show_menu, false)
```

- [ ] **Step 2: Add toggle_menu and close_menu event handlers**

In `lib/web/live/family_live/show.ex`, add:

```elixir
def handle_event("toggle_menu", _, socket) do
  {:noreply, assign(socket, :show_menu, !socket.assigns.show_menu)}
end

def handle_event("close_menu", _, socket) do
  {:noreply, assign(socket, :show_menu, false)}
end
```

- [ ] **Step 3: Replace toolbar buttons with meatball dropdown in the template**

In `lib/web/live/family_live/show.html.heex`, replace the Manage People link (lines 69-77) and Create Subfamily button (lines 78-89) with a meatball menu. Keep Kinship, Edit, and Delete as direct buttons. After the Delete button, add:

```heex
<%!-- Meatball menu --%>
<div class="relative" {test_id("meatball-menu")}>
  <button
    type="button"
    phx-click="toggle_menu"
    class="p-2 text-ds-on-surface-variant hover:text-ds-on-surface"
    aria-label="More actions"
    {test_id("meatball-btn")}
  >
    <.icon name="hero-ellipsis-horizontal" class="size-5" />
  </button>

  <div
    :if={@show_menu}
    phx-click-away="close_menu"
    class="absolute right-0 top-full mt-1 w-56 bg-ds-surface-card rounded-lg shadow-ds-ambient border border-ds-outline-variant py-1 z-50"
    {test_id("meatball-dropdown")}
  >
    <.link
      navigate={~p"/org/#{@current_scope.organization.id}/families/#{@family.id}/people"}
      class="flex items-center gap-3 px-4 py-2.5 text-sm text-ds-on-surface hover:bg-ds-surface-low transition-colors"
    >
      <.icon name="hero-user-group" class="size-4 text-ds-on-surface-variant" />
      <span>Manage people</span>
    </.link>

    <%= if @people != [] do %>
      <button
        type="button"
        phx-click={JS.push("close_menu") |> JS.push("open_create_subfamily")}
        class="flex items-center gap-3 w-full px-4 py-2.5 text-sm text-left text-ds-on-surface hover:bg-ds-surface-low transition-colors"
      >
        <.icon name="hero-square-2-stack" class="size-4 text-ds-on-surface-variant" />
        <span>Create subfamily</span>
      </button>
    <% end %>

    <button
      type="button"
      phx-click={JS.push("close_menu") |> JS.push("open_import")}
      class="flex items-center gap-3 w-full px-4 py-2.5 text-sm text-left text-ds-on-surface hover:bg-ds-surface-low transition-colors"
      {test_id("import-csv-btn")}
    >
      <.icon name="hero-arrow-up-tray" class="size-4 text-ds-on-surface-variant" />
      <span>Import from CSV</span>
    </button>
  </div>
</div>
```

Remove the old standalone Manage People link and Create Subfamily button that were in the toolbar directly.

- [ ] **Step 4: Fix existing E2E tests that click relocated buttons**

Two existing E2E tests click toolbar buttons that now live inside the meatball dropdown. Update them to open the meatball menu first:

**In `test/user_flows/create_subfamily_test.exs`:** Before every `click(test_id("family-create-subfamily-btn"))`, add:
```elixir
|> click(test_id("meatball-btn"))
```
Note: the Create Subfamily button no longer has `test_id("family-create-subfamily-btn")` as a standalone toolbar button. Update the test to click the meatball menu text "Create subfamily" instead, or add a `test_id` to the meatball menu item. The meatball dropdown item does not have a test_id — add `{test_id("family-create-subfamily-btn")}` to the Create Subfamily button inside the meatball dropdown template (Task 2, Step 3) to preserve the existing test selector.

**In `test/user_flows/manage_people_test.exs`:** Similarly, before every `click(test_id("family-manage-people-btn"))`, add:
```elixir
|> click(test_id("meatball-btn"))
```
Add `{test_id("family-manage-people-btn")}` to the Manage People link inside the meatball dropdown template.

- [ ] **Step 5: Run the affected E2E tests**

Run: `mix test test/user_flows/create_subfamily_test.exs test/user_flows/manage_people_test.exs --seed 0`
Expected: Both tests pass with the meatball menu interaction.

- [ ] **Step 6: Commit**

```bash
git add lib/web/live/family_live/show.ex lib/web/live/family_live/show.html.heex test/user_flows/create_subfamily_test.exs test/user_flows/manage_people_test.exs
git commit -m "Add meatball overflow menu to family show toolbar"
```

---

### Task 3: Add CSV import modal — upload form state

**Files:**
- Modify: `lib/web/live/family_live/show.ex` (add import assigns, `allow_upload`, event handlers)
- Modify: `lib/web/live/family_live/show.html.heex` (add import modal markup)

- [ ] **Step 1: Add import assigns and allow_upload to mount**

In `lib/web/live/family_live/show.ex` mount, add:

```elixir
|> assign(:show_import_modal, false)
|> assign(:import_summary, nil)
|> assign(:import_error, nil)
|> allow_upload(:csv_file,
  accept: ~w(.csv),
  max_entries: 1,
  max_file_size: 10_000_000
)
```

- [ ] **Step 2: Add open_import and close_import event handlers**

```elixir
# CSV import

def handle_event("open_import", _, socket) do
  {:noreply,
   socket
   |> assign(:show_import_modal, true)
   |> assign(:import_summary, nil)
   |> assign(:import_error, nil)}
end

def handle_event("close_import", _, socket) do
  family = socket.assigns.family
  people = People.list_people_for_family(family.id)
  metrics = Metrics.compute(family.id)
  focus_person = socket.assigns.focus_person

  # Refresh focus_person from updated list (same pattern as handle_info :relationship_saved)
  focus_person =
    if focus_person do
      Enum.find(people, &(&1.id == focus_person.id))
    end

  tree =
    if focus_person do
      PersonTree.build(focus_person, family.id)
    end

  {:noreply,
   socket
   |> assign(:show_import_modal, false)
   |> assign(:import_summary, nil)
   |> assign(:import_error, nil)
   |> assign(:people, people)
   |> assign(:focus_person, focus_person)
   |> assign(:tree, tree)
   |> assign(:metrics, Phoenix.LiveView.AsyncResult.ok(metrics))}
end
```

- [ ] **Step 3: Add the import modal template (upload form state)**

Add to the bottom of `lib/web/live/family_live/show.html.heex`, before the closing `</Layouts.app>`:

```heex
<%!-- Import CSV modal --%>
<div
  :if={@show_import_modal}
  class="fixed inset-0 z-50 flex items-end lg:items-center justify-center"
  {test_id("import-modal")}
>
  <%!-- Backdrop --%>
  <div class="absolute inset-0 bg-black/50" phx-click="close_import" />

  <%!-- Modal --%>
  <div class="relative w-full max-w-none lg:max-w-md bg-ds-surface-card rounded-t-lg lg:rounded-ds-sharp shadow-ds-ambient p-6">
    <%= if @import_error do %>
      <%!-- Error state --%>
      <h2 class="font-ds-heading font-bold text-lg text-ds-on-surface mb-4">Import failed</h2>
      <p class="text-sm text-ds-signal-error mb-6">{@import_error}</p>
      <button
        type="button"
        phx-click="close_import"
        class="w-full py-2.5 px-4 bg-ds-surface-low text-ds-on-surface text-sm font-medium rounded-lg hover:bg-ds-surface-high transition-colors"
      >
        Close
      </button>
    <% else %>
      <%= if @import_summary do %>
        <%!-- Results state --%>
        <h2 class="font-ds-heading font-bold text-lg text-ds-on-surface mb-4">Import complete</h2>
        <dl class="space-y-2 mb-4">
          <div class="flex justify-between">
            <dt class="text-sm text-ds-on-surface-variant">People added</dt>
            <dd class="text-sm font-medium text-ds-on-surface" {test_id("import-created")}>
              {@import_summary.people_created}
            </dd>
          </div>
          <div class="flex justify-between">
            <dt class="text-sm text-ds-on-surface-variant">Already existing</dt>
            <dd class="text-sm font-medium text-ds-on-surface" {test_id("import-existing")}>
              {@import_summary.people_unchanged + @import_summary.people_updated}
            </dd>
          </div>
          <div class="flex justify-between">
            <dt class="text-sm text-ds-on-surface-variant">Errors</dt>
            <dd class="text-sm font-medium text-ds-on-surface" {test_id("import-errors")}>
              {@import_summary.people_skipped}
            </dd>
          </div>
        </dl>

        <%= if @import_summary.people_errors != [] do %>
          <div class="mb-4">
            <h3 class="text-sm font-medium text-ds-on-surface mb-2">Error details</h3>
            <ul
              class="max-h-60 overflow-y-auto space-y-1 text-xs text-ds-on-surface-variant bg-ds-surface-low rounded-lg p-3"
              {test_id("import-error-list")}
            >
              <%= for error <- @import_summary.people_errors do %>
                <li>{error}</li>
              <% end %>
            </ul>
          </div>
        <% end %>

        <button
          type="button"
          phx-click="close_import"
          class="w-full py-2.5 px-4 bg-ds-surface-low text-ds-on-surface text-sm font-medium rounded-lg hover:bg-ds-surface-high transition-colors"
          {test_id("import-close-btn")}
        >
          Close
        </button>
      <% else %>
        <%!-- Upload form state --%>
        <h2 class="font-ds-heading font-bold text-lg text-ds-on-surface mb-4">Import from CSV</h2>

        <form id="import-form" phx-change="validate_import" phx-submit="import_csv">
          <div class="mb-4">
            <.input
              type="select"
              name="format"
              label="Format"
              value="family_echo"
              options={[{"Family Echo", "family_echo"}]}
            />
          </div>

          <div class="mb-4">
            <label class="block text-sm font-medium text-ds-on-surface mb-1">CSV file</label>
            <.live_file_input
              upload={@uploads.csv_file}
              class="block w-full text-sm text-ds-on-surface-variant file:mr-4 file:py-2 file:px-4 file:rounded-lg file:border-0 file:text-sm file:font-medium file:bg-ds-surface-low file:text-ds-on-surface hover:file:bg-ds-surface-high"
              {test_id("import-file-input")}
            />
            <%= for entry <- @uploads.csv_file.entries do %>
              <p class="text-xs text-ds-on-surface-variant mt-1">{entry.client_name}</p>
              <%= for err <- upload_errors(@uploads.csv_file, entry) do %>
                <p class="text-xs text-ds-signal-error mt-1">{upload_error_to_string(err)}</p>
              <% end %>
            <% end %>
          </div>

          <div class="flex gap-3">
            <button
              type="button"
              phx-click="close_import"
              class="flex-1 py-2.5 px-4 bg-ds-surface-low text-ds-on-surface text-sm font-medium rounded-lg hover:bg-ds-surface-high transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={@uploads.csv_file.entries == []}
              class="flex-1 py-2.5 px-4 bg-ds-on-surface text-ds-surface text-sm font-medium rounded-lg hover:opacity-90 transition-opacity disabled:opacity-40"
              {test_id("import-submit-btn")}
            >
              Import
            </button>
          </div>
        </form>
      <% end %>
    <% end %>
  </div>
</div>
```

- [ ] **Step 4: Add `validate_import` event handler** (required for `phx-change` on the upload form)

```elixir
def handle_event("validate_import", _params, socket) do
  {:noreply, socket}
end
```

- [ ] **Step 5: Add `upload_error_to_string` helper**

In `lib/web/live/family_live/show.ex`, add a private helper:

```elixir
defp upload_error_to_string(:too_large), do: "File is too large (max 10MB)"
defp upload_error_to_string(:not_accepted), do: "Only .csv files are accepted"
defp upload_error_to_string(:too_many_files), do: "Only one file can be uploaded"
defp upload_error_to_string(err), do: "Upload error: #{inspect(err)}"
```

- [ ] **Step 6: Verify the modal renders**

Run: `mix compile --warnings-as-errors`
Expected: Clean compilation.

- [ ] **Step 7: Commit**

```bash
git add lib/web/live/family_live/show.ex lib/web/live/family_live/show.html.heex
git commit -m "Add CSV import modal with upload form and results states"
```

---

### Task 4: Wire up the import execution

**Files:**
- Modify: `lib/web/live/family_live/show.ex` (add `import_csv` event handler)

- [ ] **Step 1: Add the `import_csv` event handler**

In `lib/web/live/family_live/show.ex`, add:

```elixir
def handle_event("import_csv", _params, socket) do
  family = socket.assigns.family

  [result] =
    consume_uploaded_entries(socket, :csv_file, fn %{path: path}, _entry ->
      try do
        {:ok, Ancestry.Import.import_csv_for_family(:family_echo, family, path)}
      rescue
        e in [NimbleCSV.ParseError] ->
          {:ok, {:error, "Could not parse CSV file: #{Exception.message(e)}"}}

        _e in [MatchError] ->
          {:ok, {:error, "CSV file is empty or has no data rows"}}

        _ ->
          {:ok, {:error, "Could not parse CSV file"}}
      end
    end)

  case result do
    {:ok, summary} ->
      {:noreply, assign(socket, :import_summary, summary)}

    {:error, reason} ->
      {:noreply, assign(socket, :import_error, reason)}
  end
end
```

- [ ] **Step 2: Run the full test suite to check for regressions**

Run: `mix test --seed 0`
Expected: All existing tests pass.

- [ ] **Step 3: Commit**

```bash
git add lib/web/live/family_live/show.ex
git commit -m "Wire up CSV import execution with error handling"
```

---

### Task 5: E2E test for the import flow

**Files:**
- Create: `test/user_flows/csv_import_test.exs`
- Create: `test/fixtures/family_echo_sample.csv` (test fixture)

- [ ] **Step 1: Create the test CSV fixture**

Create `test/fixtures/family_echo_sample.csv` with the full Family Echo header row and 2 data rows. Use the same 67-column header list from `test/ancestry/import/csv_test.exs` (`@headers`). Data rows should have IDs, given names, surnames, and gender filled in; leave other columns empty. Example people: "Alice,Smith,Female" and "Bob,Smith,Male".

- [ ] **Step 2: Write the E2E test**

Create `test/user_flows/csv_import_test.exs`:

```elixir
defmodule Web.UserFlows.CsvImportTest do
  use Web.E2ECase

  # Given an existing family in an organization
  # When the user navigates to the family show page
  # And clicks the meatball menu
  # Then the dropdown with secondary actions is visible
  #
  # When the user clicks "Import from CSV"
  # Then the import modal is shown with an upload form
  #
  # When the user selects a CSV file
  # And clicks "Import"
  # Then the modal shows the import results
  # And the people count reflects the imported people
  #
  # When the user clicks "Close"
  # Then the modal closes
  # And the imported people appear in the sidebar

  setup do
    org = insert(:organization, name: "Test Org")
    family = insert(:family, name: "Import Family", organization: org)
    %{org: org, family: family}
  end

  test "import people from CSV via meatball menu", %{conn: conn, org: org, family: family} do
    conn = log_in_e2e(conn)

    # Navigate to family show page
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}")
      |> wait_liveview()
      |> assert_has(test_id("family-name"), text: "Import Family")

    # Open meatball menu
    conn =
      conn
      |> click(test_id("meatball-btn"))
      |> assert_has(test_id("meatball-dropdown"))

    # Click "Import from CSV"
    conn =
      conn
      |> click(test_id("import-csv-btn"))
      |> assert_has(test_id("import-modal"))

    # Upload CSV file (reuses upload_image which handles any file via mime_for_extension)
    conn =
      conn
      |> upload_image(
        test_id("import-file-input"),
        [Path.absname("test/fixtures/family_echo_sample.csv")]
      )

    # Submit the import form
    conn =
      conn
      |> click(test_id("import-submit-btn"))
      |> assert_has(test_id("import-created"))

    # Close the modal
    conn
    |> click(test_id("import-close-btn"))
    |> refute_has(test_id("import-modal"))
  end
end
```

- [ ] **Step 3: Add CSV mime type to `Web.E2ECase`**

In `test/support/e2e_case.ex`, add a new clause to the existing `mime_for_extension` function:

```elixir
defp mime_for_extension(".csv"), do: "text/csv"
```

Then reuse the existing `upload_image` helper for CSV uploads (it already uses `mime_for_extension` to determine the MIME type from the file extension). The E2E test calls `upload_image` with the CSV file path — no new helper needed.

- [ ] **Step 4: Run the E2E test**

Run: `mix test test/user_flows/csv_import_test.exs --seed 0`
Expected: Test passes end-to-end.

- [ ] **Step 5: Commit**

```bash
git add test/user_flows/csv_import_test.exs test/fixtures/family_echo_sample.csv test/support/e2e_case.ex
git commit -m "Add E2E test for CSV import from family show page"
```

---

### Task 5b: Update existing E2E tests for meatball menu

**Files:**
- Modify: `test/user_flows/create_subfamily_test.exs` (add meatball menu open step)
- Modify: `test/user_flows/manage_people_test.exs` (add meatball menu open step)

- [ ] **Step 1: Update create_subfamily_test.exs**

Find every `click(test_id("family-create-subfamily-btn"))` and prepend a meatball menu open:

```elixir
|> click(test_id("meatball-btn"))
|> click(test_id("family-create-subfamily-btn"))
```

- [ ] **Step 2: Update manage_people_test.exs**

Find every `click(test_id("family-manage-people-btn"))` and prepend a meatball menu open:

```elixir
|> click(test_id("meatball-btn"))
|> click(test_id("family-manage-people-btn"))
```

- [ ] **Step 3: Run the updated tests**

Run: `mix test test/user_flows/create_subfamily_test.exs test/user_flows/manage_people_test.exs --seed 0`
Expected: Both pass.

- [ ] **Step 4: Commit**

```bash
git add test/user_flows/create_subfamily_test.exs test/user_flows/manage_people_test.exs
git commit -m "Update E2E tests for meatball menu interaction"
```

---

### Task 6: Run precommit and fix any issues

- [ ] **Step 1: Run precommit**

Run: `mix precommit`
Expected: Clean pass — compilation (warnings-as-errors), formatting, unused deps, and all tests pass.

- [ ] **Step 2: Fix any issues**

Address any warnings, formatting issues, or failing tests.

- [ ] **Step 3: Final commit if needed**

```bash
git add -A
git commit -m "Fix precommit issues"
```
