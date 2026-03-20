# Compact People Table Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Refactor PeopleLive.Index to a compact CSS grid table with actions column, clickable names, and back navigation from PersonLive.Show to the people page.

**Architecture:** Template-only refactor for the grid layout. Add `request_remove_person` event to the LiveView for single-row removal. Modify PersonLive.Show `handle_params` to support `from_people` and `editing` query params.

**Tech Stack:** Phoenix LiveView, Tailwind CSS grid, E2E tests with PhoenixTest.Playwright.

---

### Task 1: Refactor template to CSS grid table

**Files:**
- Modify: `lib/web/live/people_live/index.html.heex`

**Step 1: Rewrite the template**

Replace the entire content between the search box and the confirmation modal (lines 66–180) with a CSS grid table. Keep the toolbar (lines 1–42), search box (lines 44–64), and confirmation modal (lines 182–214) unchanged.

The new table structure:

```heex
<%!-- Column headers (hidden on mobile) --%>
<div class="px-4 pb-8 w-full">
  <div class="hidden sm:grid sm:grid-cols-[2rem_1fr_8rem_7rem_4rem] sm:gap-x-3 sm:items-center px-3 py-1 text-xs font-medium text-base-content/40 uppercase tracking-wider"
    <%= if @editing do %>
      style="grid-template-columns: 1.25rem 2rem 1fr 8rem 7rem 4rem"
    <% end %>
  >
    <%= if @editing do %>
      <div>
        <%!-- select all checkbox --%>
      </div>
    <% end %>
    <div></div>
    <div>Name</div>
    <div>Lifespan</div>
    <div>Relationships</div>
    <div></div>
  </div>

  <%!-- Stream table --%>
  <div id="people-table" phx-update="stream" {test_id("people-table")}>
    <div id="people-empty-state" class="hidden only:block py-16 text-center">
      ...
    </div>
    <div
      :for={{dom_id, {person, rel_count}} <- @streams.people}
      id={dom_id}
      class={[
        "grid gap-x-3 items-center px-3 py-1.5 hover:bg-base-200/50 transition-colors border-b border-base-200/60 last:border-b-0",
        "grid-cols-[2rem_1fr_auto] sm:grid-cols-[2rem_1fr_8rem_7rem_4rem]",
        @editing && "grid-cols-[1.25rem_2rem_1fr_auto] sm:grid-cols-[1.25rem_2rem_1fr_8rem_7rem_4rem]"
      ]}
      {test_id("people-row-#{person.id}")}
    >
      <%!-- checkbox (edit mode only) --%>
      <%!-- photo (32px) --%>
      <%!-- name (link) + mobile lifespan/rels --%>
      <%!-- lifespan (hidden on mobile, shown below name) --%>
      <%!-- relationships (hidden on mobile, shown below name) --%>
      <%!-- actions --%>
    </div>
  </div>
</div>
```

**Key changes from the current template:**

1. **Remove `max-w-4xl mx-auto`** — use full width with `px-4`
2. **Remove the separate "select all / deselect all" bar** — integrate select all into the column header row (checkbox column header)
3. **Photo: 32px** (was 40px) — `w-8 h-8` instead of `w-10 h-10`
4. **Row padding: `py-1.5`** (was `py-3`)
5. **Name becomes a link** to `/people/:id?from_family=:family_id&from_people=true`
6. **Lifespan column** — separate grid cell on `sm:`, stacked below name on mobile (use `sm:hidden` for the mobile version, `hidden sm:block` for desktop version)
7. **Relationships column** — same responsive pattern as lifespan
8. **Actions column** — two icon-only buttons:
   - Edit: `hero-pencil-square` (16x16), links to `/people/:id?from_family=:family_id&from_people=true&editing=true`
   - Remove: `hero-x-mark` (16x16), triggers `phx-click="request_remove_person"` with `phx-value-id={person.id}`
   - Add `test_id("people-edit-person-#{person.id}")` and `test_id("people-remove-person-#{person.id}")`
9. **Select all / deselect all** — in the header row, the checkbox column header is a clickable toggle. Plus keep the "N selected" counter next to it or in the toolbar.

**Mobile layout (< sm):**
- Grid: `grid-cols-[2rem_1fr_auto]` (photo, name+stacked-info, actions)
- With edit: `grid-cols-[1.25rem_2rem_1fr_auto]` (checkbox, photo, name+stacked-info, actions)
- Lifespan and relationship count appear below the name as `text-xs` dim text
- The separate desktop lifespan/relationships columns are `hidden sm:block`

**Step 2: Verify it compiles**

Run: `mix compile --warnings-as-errors`

**Step 3: Commit**

```
git add lib/web/live/people_live/index.html.heex
git commit -m "refactor: convert people table to compact CSS grid layout"
```

---

### Task 2: Add request_remove_person event for single-row removal

**Files:**
- Modify: `lib/web/live/people_live/index.ex`

**Step 1: Add the event handler**

Add a new `handle_event` clause in `lib/web/live/people_live/index.ex` after the existing `request_remove` handler (around line 91):

```elixir
def handle_event("request_remove_person", %{"id" => id}, socket) do
  person_id = String.to_integer(id)

  {:noreply,
   socket
   |> assign(:selected, MapSet.new([person_id]))
   |> assign(:confirm_remove, true)}
end
```

This reuses the existing confirmation modal by setting `@selected` to just this one person and opening the modal. The `confirm_remove` handler already handles the rest.

**Step 2: Verify it compiles**

Run: `mix compile --warnings-as-errors`

**Step 3: Commit**

```
git add lib/web/live/people_live/index.ex
git commit -m "feat: add single-row remove action for people table"
```

---

### Task 3: Update PersonLive.Show for from_people and editing params

**Files:**
- Modify: `lib/web/live/person_live/show.ex`
- Modify: `lib/web/live/person_live/show.html.heex`

**Step 1: Update handle_params to read new query params**

In `lib/web/live/person_live/show.ex`, modify `handle_params` (line 39–46):

```elixir
@impl true
def handle_params(params, _url, socket) do
  from_family =
    case params do
      %{"from_family" => family_id} -> Families.get_family!(family_id)
      _ -> nil
    end

  from_people = params["from_people"] == "true"

  editing =
    if params["editing"] == "true" and not socket.assigns.editing do
      true
    else
      socket.assigns.editing
    end

  socket =
    socket
    |> assign(:from_family, from_family)
    |> assign(:from_people, from_people)

  # Auto-enter edit mode if editing=true param is present
  socket =
    if editing and not socket.assigns.editing do
      person = socket.assigns.person

      extra_fields_present? =
        birth_name_differs?(person.given_name_at_birth, person.given_name) ||
          birth_name_differs?(person.surname_at_birth, person.surname) ||
          has_value?(person.nickname) ||
          has_value?(person.title) ||
          has_value?(person.suffix) ||
          (person.alternate_names != nil and person.alternate_names != [])

      assign(socket,
        editing: true,
        form: to_form(People.change_person(person)),
        show_extra_fields: extra_fields_present?
      )
    else
      socket
    end

  {:noreply, socket}
end
```

Note: The edit initialization logic must match what the existing `handle_event("edit", ...)` does (lines 50-70 of show.ex). Read the full `edit` event handler and replicate the same assigns.

**Step 2: Add `from_people` assign to mount**

In `mount/3` (line 21), add after `:from_family`:

```elixir
|> assign(:from_people, false)
```

**Step 3: Update back button in template**

In `lib/web/live/person_live/show.html.heex`, replace the back button logic (lines 5-18):

```heex
<%= cond do %>
  <% @from_family && @from_people -> %>
    <.link
      navigate={~p"/families/#{@from_family.id}/people"}
      class="p-2 rounded-lg text-base-content/40 hover:text-base-content hover:bg-base-200 transition-colors"
    >
      <.icon name="hero-arrow-left" class="w-5 h-5" />
    </.link>
  <% @from_family -> %>
    <.link
      navigate={~p"/families/#{@from_family.id}?person=#{@person.id}"}
      class="p-2 rounded-lg text-base-content/40 hover:text-base-content hover:bg-base-200 transition-colors"
    >
      <.icon name="hero-arrow-left" class="w-5 h-5" />
    </.link>
  <% true -> %>
    <.link
      navigate={~p"/"}
      class="p-2 rounded-lg text-base-content/40 hover:text-base-content hover:bg-base-200 transition-colors"
    >
      <.icon name="hero-arrow-left" class="w-5 h-5" />
    </.link>
<% end %>
```

**Step 4: Update person_path helper to preserve from_people**

In `lib/web/live/person_live/show.ex`, update the `person_path/2` helper (line 476–482). It needs to accept `from_people` as well. Change to `person_path/3`:

```elixir
defp person_path(person, from_family, from_people) do
  cond do
    from_family && from_people ->
      ~p"/people/#{person.id}?from_family=#{from_family.id}&from_people=true"
    from_family ->
      ~p"/people/#{person.id}?from_family=#{from_family.id}"
    true ->
      ~p"/people/#{person.id}"
  end
end
```

Then update ALL calls to `person_path/2` in the template to `person_path/3`, passing `@from_people` as the third argument. Search for `person_path(` in `show.html.heex` and `show.ex` to find all call sites.

**Step 5: Verify it compiles**

Run: `mix compile --warnings-as-errors`

**Step 6: Commit**

```
git add lib/web/live/person_live/show.ex lib/web/live/person_live/show.html.heex
git commit -m "feat: support from_people and editing query params in PersonLive.Show"
```

---

### Task 4: Update E2E tests

**Files:**
- Modify: `test/user_flows/manage_people_test.exs`

**Step 1: Add new test cases**

Add these tests to the existing test file:

```elixir
test "click name navigates to person show and back returns to people page", %{
  conn: conn,
  family: family,
  bob: bob
} do
  conn =
    conn
    |> visit(~p"/families/#{family.id}/people")
    |> wait_liveview()

  # Click Bob's name link
  conn =
    conn
    |> click(test_id("people-name-#{bob.id}"))
    |> wait_liveview()

  # Should be on person show page
  conn =
    conn
    |> assert_has("h1", text: "Bob Smith")

  # Click back button — should return to people page
  conn =
    conn
    |> click("a[href*='/people']", text: "") # back arrow link — target the first link in toolbar
    |> wait_liveview()

  # Should be back on people page
  conn
  |> assert_has(test_id("people-table"))
end

test "edit action navigates to person show in edit mode", %{
  conn: conn,
  family: family,
  bob: bob
} do
  conn =
    conn
    |> visit(~p"/families/#{family.id}/people")
    |> wait_liveview()

  # Click edit icon for Bob
  conn =
    conn
    |> click(test_id("people-edit-person-#{bob.id}"))
    |> wait_liveview()

  # Should be on person show page in edit mode (form visible)
  conn
  |> assert_has("h1", text: "Bob Smith")
  |> assert_has("form")
end

test "remove action on single row shows confirmation and removes person", %{
  conn: conn,
  family: family,
  diana: diana
} do
  conn =
    conn
    |> visit(~p"/families/#{family.id}/people")
    |> wait_liveview()

  # Click remove icon for Diana
  conn =
    conn
    |> click(test_id("people-remove-person-#{diana.id}"))
    |> wait_liveview()

  # Confirmation modal should appear with "1 person"
  conn =
    conn
    |> assert_has(test_id("people-confirm-remove-modal"))
    |> assert_has(test_id("people-confirm-remove-modal"), text: "1")

  # Confirm removal
  conn =
    conn
    |> click(test_id("people-confirm-remove-btn"))
    |> wait_liveview()

  # Diana should be gone
  conn
  |> refute_has(test_id("people-table"), text: "Williams, Diana", timeout: 5_000)
  |> assert_has(test_id("people-table"), text: "Smith, Alice")
end
```

**Step 2: Run all E2E tests**

Run: `mix test test/user_flows/manage_people_test.exs`
Expected: All tests PASS (existing + new)

**Step 3: Commit**

```
git add test/user_flows/manage_people_test.exs
git commit -m "test: add E2E tests for actions column and back navigation"
```

---

### Task 5: Run precommit and fix issues

**Step 1: Run precommit**

Run: `mix precommit`
Expected: All checks pass

**Step 2: Fix any issues**

Address compilation warnings, formatting, or test failures.

**Step 3: Final commit if needed**

```
git add -A
git commit -m "chore: fix precommit issues"
```
