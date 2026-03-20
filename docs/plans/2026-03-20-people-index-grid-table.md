# People Index CSS Grid Table Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the people index page from a flex-based list to a CSS Grid table with estimated age, lifespan, alive/deceased indicator, per-row unlink, warning icons for 0-link people, and an "Unlinked" quick filter chip.

**Architecture:** The stream container becomes a CSS Grid. Each streamed row uses `display: contents` so its cells participate in the parent grid. The context query gains an `unlinked_only` filter option. A new `estimated_age/1` helper computes age from birth/death years.

**Tech Stack:** Phoenix LiveView, CSS Grid, DaisyUI (indicator badge), Tailwind CSS, Ecto (query filter), PhoenixTest.Playwright (E2E tests)

**Spec:** `docs/superpowers/specs/2026-03-20-people-index-grid-table-design.md`

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `lib/ancestry/people.ex` | Modify | Add `unlinked_only` filter option to `list_people_for_family_with_relationship_counts` |
| `lib/web/live/people_live/index.ex` | Modify | Add `:unlinked_only` assign, `estimated_age/1` helper, `toggle_unlinked` + `request_remove_one` events, pass `unlinked_only` to query |
| `lib/web/live/people_live/index.html.heex` | Rewrite | CSS Grid table with header, 6 columns (7 in edit mode), DaisyUI indicator, unlinked chip, per-row unlink button |
| `assets/css/app.css` | Modify | Add zebra striping rule for `#people-table` |
| `test/user_flows/manage_people_test.exs` | Modify | Update existing tests for new markup, add tests for new features |

---

### Task 1: Add `unlinked_only` filter to the People context

**Files:**
- Modify: `lib/ancestry/people.ex:19-80`

The existing three function heads are restructured: a shared `base_people_query/1` builds the common query, and `maybe_filter_unlinked/2` conditionally adds the HAVING clause.

**Important:** The 2-arity variant uses `opts \\ []` default. The 3-arity variant does NOT use a default (to avoid Elixir clause ambiguity). Callers with a search term must pass opts explicitly.

- [ ] **Step 1: Add `base_people_query/1` private function**

Add at the bottom of `lib/ancestry/people.ex`:

```elixir
defp base_people_query(family_id) do
  from p in Person,
    join: fm in FamilyMember,
    on: fm.person_id == p.id and fm.family_id == ^family_id,
    left_join: r in Relationship,
    as: :rel,
    on: r.person_a_id == p.id or r.person_b_id == p.id,
    left_join: fm_other in FamilyMember,
    as: :fm_other,
    on:
      fm_other.family_id == ^family_id and
        ((r.person_a_id == p.id and fm_other.person_id == r.person_b_id) or
           (r.person_b_id == p.id and fm_other.person_id == r.person_a_id)),
    group_by: p.id,
    order_by: [asc: p.surname, asc: p.given_name],
    select:
      {p,
       fragment(
         "COUNT(DISTINCT CASE WHEN ? IS NOT NULL THEN ? END)",
         fm_other.id,
         r.id
       )}
end
```

- [ ] **Step 2: Add `maybe_filter_unlinked/2` private function**

```elixir
defp maybe_filter_unlinked(query, true) do
  having(query, [rel: r, fm_other: fm_other],
    fragment(
      "COUNT(DISTINCT CASE WHEN ? IS NOT NULL THEN ? END) = 0",
      fm_other.id,
      r.id
    )
  )
end

defp maybe_filter_unlinked(query, false), do: query
```

- [ ] **Step 3: Replace the three public function heads**

Replace all three existing `list_people_for_family_with_relationship_counts` function heads with:

```elixir
def list_people_for_family_with_relationship_counts(family_id, opts \\ []) do
  unlinked_only = Keyword.get(opts, :unlinked_only, false)

  base_people_query(family_id)
  |> maybe_filter_unlinked(unlinked_only)
  |> Repo.all()
end

def list_people_for_family_with_relationship_counts(family_id, "", opts),
  do: list_people_for_family_with_relationship_counts(family_id, opts)

def list_people_for_family_with_relationship_counts(family_id, search_term, opts) do
  unlinked_only = Keyword.get(opts, :unlinked_only, false)

  escaped =
    search_term
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")

  like = "%#{escaped}%"

  base_people_query(family_id)
  |> where([p],
    fragment("unaccent(?) ILIKE unaccent(?)", p.given_name, ^like) or
      fragment("unaccent(?) ILIKE unaccent(?)", p.surname, ^like) or
      fragment("unaccent(?) ILIKE unaccent(?)", p.nickname, ^like)
  )
  |> maybe_filter_unlinked(unlinked_only)
  |> Repo.all()
end
```

Note: The 3-arity variant has no default on `opts` — callers must pass it explicitly (e.g. `list_people_for_family_with_relationship_counts(id, query, unlinked_only: true)` or `list_people_for_family_with_relationship_counts(id, query, [])`).

- [ ] **Step 4: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compilation succeeds with no warnings.

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/people.ex
git commit -m "feat: add unlinked_only filter to people relationship query"
```

---

### Task 2: Add LiveView assigns, events, and helpers

**Files:**
- Modify: `lib/web/live/people_live/index.ex`

- [ ] **Step 1: Add `estimated_age/1` helper**

Add a private function at the bottom of `index.ex`:

```elixir
defp estimated_age(%{birth_year: nil}), do: nil

defp estimated_age(%{deceased: true, death_year: nil}), do: nil

defp estimated_age(%{deceased: true, birth_year: birth_year, death_year: death_year}),
  do: death_year - birth_year

defp estimated_age(%{birth_year: birth_year}),
  do: Date.utc_today().year - birth_year
```

- [ ] **Step 2: Add `:unlinked_only` assign to mount**

Add `|> assign(:unlinked_only, false)` to the mount pipeline:

```elixir
def mount(%{"family_id" => family_id}, _session, socket) do
  family = Families.get_family!(family_id)
  people = People.list_people_for_family_with_relationship_counts(family_id)

  {:ok,
   socket
   |> assign(:family, family)
   |> assign(:filter, "")
   |> assign(:editing, false)
   |> assign(:selected, MapSet.new())
   |> assign(:confirm_remove, false)
   |> assign(:unlinked_only, false)
   |> assign(:people_empty?, people == [])
   |> stream_configure(:people, dom_id: fn {person, _rel_count} -> "people-#{person.id}" end)
   |> stream(:people, people)}
end
```

- [ ] **Step 3: Add `toggle_unlinked` event handler**

```elixir
def handle_event("toggle_unlinked", _, socket) do
  unlinked_only = !socket.assigns.unlinked_only
  people = refetch_people(socket, unlinked_only: unlinked_only)

  {:noreply,
   socket
   |> assign(:unlinked_only, unlinked_only)
   |> assign(:selected, MapSet.new())
   |> assign(:people_empty?, people == [])
   |> stream(:people, people, reset: true)}
end
```

- [ ] **Step 4: Add `request_remove_one` event handler**

```elixir
def handle_event("request_remove_one", %{"id" => id}, socket) do
  if socket.assigns.confirm_remove do
    {:noreply, socket}
  else
    person_id = String.to_integer(id)

    {:noreply,
     socket
     |> assign(:selected, MapSet.new([person_id]))
     |> assign(:confirm_remove, true)}
  end
end
```

- [ ] **Step 5: Update `refetch_people/1` to pass `unlinked_only`**

Replace the existing `refetch_people/1` with a version that accepts opts and uses the socket's `unlinked_only` assign:

```elixir
defp refetch_people(socket, opts \\ []) do
  unlinked_only = Keyword.get(opts, :unlinked_only, socket.assigns.unlinked_only)

  People.list_people_for_family_with_relationship_counts(
    socket.assigns.family.id,
    socket.assigns.filter,
    unlinked_only: unlinked_only
  )
end
```

- [ ] **Step 6: Update existing event handlers to use `refetch_people` or pass `unlinked_only`**

Update `handle_event("filter", ...)` to pass opts:

```elixir
def handle_event("filter", %{"filter" => query}, socket) do
  family_id = socket.assigns.family.id

  people =
    People.list_people_for_family_with_relationship_counts(family_id, query,
      unlinked_only: socket.assigns.unlinked_only
    )

  {:noreply,
   socket
   |> assign(:filter, query)
   |> assign(:selected, MapSet.new())
   |> assign(:people_empty?, people == [])
   |> stream(:people, people, reset: true)}
end
```

Update `handle_event("toggle_edit", ...)` — uses `refetch_people` which now passes `unlinked_only` from the socket:

```elixir
def handle_event("toggle_edit", _, socket) do
  editing = !socket.assigns.editing
  people = refetch_people(socket)

  {:noreply,
   socket
   |> assign(:editing, editing)
   |> assign(:selected, MapSet.new())
   |> stream(:people, people, reset: true)}
end
```

Update `handle_event("confirm_remove", ...)` — uses `refetch_people`:

```elixir
def handle_event("confirm_remove", _, socket) do
  family = socket.assigns.family
  selected = socket.assigns.selected
  count = MapSet.size(selected)

  for person_id <- selected do
    person = People.get_person!(person_id)
    People.remove_from_family(person, family)
  end

  people = refetch_people(socket)

  {:noreply,
   socket
   |> assign(:selected, MapSet.new())
   |> assign(:confirm_remove, false)
   |> assign(:people_empty?, people == [])
   |> stream(:people, people, reset: true)
   |> put_flash(
     :info,
     "Removed #{count} #{if count == 1, do: "person", else: "people"} from the family."
   )}
end
```

Note: The `toggle_select`, `select_all`, and `deselect_all` handlers already call `refetch_people(socket)` with no overrides — the updated `refetch_people/2` defaults `unlinked_only` from `socket.assigns.unlinked_only`, so they require no changes.

- [ ] **Step 7: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compilation succeeds with no warnings.

- [ ] **Step 8: Commit**

```bash
git add lib/web/live/people_live/index.ex
git commit -m "feat: add unlinked_only, toggle_unlinked, request_remove_one, estimated_age"
```

---

### Task 3: Add zebra striping CSS

**Files:**
- Modify: `assets/css/app.css`

- [ ] **Step 1: Add the zebra striping rule**

Append to `assets/css/app.css`:

```css
/* People table zebra striping — rows use display:contents so we target cells via data-row */
#people-table > [data-row]:nth-child(even) > * {
  background-color: var(--color-base-200);
}
```

- [ ] **Step 2: Commit**

```bash
git add assets/css/app.css
git commit -m "feat: add zebra striping CSS for people grid table"
```

---

### Task 4: Rewrite the template for CSS Grid

**Files:**
- Rewrite: `lib/web/live/people_live/index.html.heex`

This is the largest task. The template is rewritten from flex rows to a CSS Grid table. The toolbar, search box, select bar, and confirmation modal remain structurally the same — only the table section and search area change.

- [ ] **Step 1: Add the "Unlinked" chip next to the search input**

Replace the search box section (lines 44-64 in current template) with:

```heex
<%!-- Search box + unlinked chip --%>
<div class="px-4 pt-4 pb-2 max-w-4xl mx-auto w-full">
  <div class="flex items-center gap-2">
    <div class="relative flex-1" {test_id("people-search")}>
      <form phx-change="filter" phx-submit="filter">
        <.icon
          name="hero-magnifying-glass"
          class="w-5 h-5 absolute left-3 top-1/2 -translate-y-1/2 text-base-content/30 pointer-events-none"
        />
        <input
          type="text"
          name="filter"
          value={@filter}
          phx-debounce="300"
          placeholder="Search people..."
          class="input input-bordered w-full pl-10"
        />
      </form>
    </div>
    <button
      phx-click="toggle_unlinked"
      class={[
        "btn btn-sm gap-1",
        if(@unlinked_only, do: "btn-warning", else: "btn-ghost")
      ]}
      {test_id("people-unlinked-chip")}
    >
      <.icon name="hero-exclamation-triangle-mini" class="w-4 h-4" /> Unlinked
    </button>
  </div>
</div>
```

- [ ] **Step 2: Add the grid header row**

Replace the table section (lines 84-180 in current template). First, the header and grid container:

```heex
<%!-- Table --%>
<div class="px-4 pb-8 max-w-4xl mx-auto w-full">
  <%!-- Header row --%>
  <div class={[
    "grid items-center border-b border-base-200 text-sm font-medium text-base-content/50",
    if(@editing,
      do: "grid-cols-[auto_auto_auto_auto_auto_auto_1fr]",
      else: "grid-cols-[auto_auto_auto_auto_auto_1fr]"
    )
  ]}>
    <%= if @editing do %>
      <div class="px-3 py-2.5"></div>
    <% end %>
    <div class="px-3 py-2.5"></div>
    <div class="px-3 py-2.5">Name</div>
    <div class="px-3 py-2.5">Est. Age</div>
    <div class="px-3 py-2.5">Lifespan</div>
    <div class="px-3 py-2.5">Links</div>
    <div class="px-3 py-2.5"></div>
  </div>
```

- [ ] **Step 3: Add the stream container with grid styling**

```heex
  <%!-- Stream rows --%>
  <div
    id="people-table"
    phx-update="stream"
    class={[
      "grid items-center",
      if(@editing,
        do: "grid-cols-[auto_auto_auto_auto_auto_auto_1fr]",
        else: "grid-cols-[auto_auto_auto_auto_auto_1fr]"
      )
    ]}
    {test_id("people-table")}
  >
    <div id="people-empty-state" class="hidden only:block col-span-full py-16 text-center">
      <.icon name="hero-users" class="w-12 h-12 mx-auto mb-3 text-base-content/20" />
      <p class="text-lg font-medium text-base-content/40">No people in this family</p>
      <p class="text-sm text-base-content/30 mt-1">
        <.link navigate={~p"/families/#{@family.id}"} class="link link-primary">
          Go back to add members
        </.link>
      </p>
    </div>
```

- [ ] **Step 4: Add each row with `display: contents` and all 6 (or 7) cells**

Note: The Name cell uses `min-w-0` to enable `truncate` within a CSS Grid `auto` column.

```heex
    <div
      :for={{dom_id, {person, rel_count}} <- @streams.people}
      id={dom_id}
      data-row
      class="contents"
      {test_id("people-row-#{person.id}")}
    >
      <%!-- Checkbox cell (edit mode only) --%>
      <%= if @editing do %>
        <div class="px-3 py-2.5">
          <button
            phx-click="toggle_select"
            phx-value-id={person.id}
            class={[
              "w-5 h-5 rounded border-2 flex items-center justify-center shrink-0 transition-colors",
              if(MapSet.member?(@selected, person.id),
                do: "bg-primary border-primary text-primary-content",
                else: "border-base-300 hover:border-primary"
              )
            ]}
            {test_id("people-checkbox-#{person.id}")}
          >
            <%= if MapSet.member?(@selected, person.id) do %>
              <.icon name="hero-check" class="w-3 h-3" />
            <% end %>
          </button>
        </div>
      <% end %>

      <%!-- Photo cell with alive/deceased indicator --%>
      <div class="px-3 py-2.5">
        <div class="indicator">
          <span
            class={[
              "indicator-item indicator-bottom indicator-end badge badge-xs",
              if(person.deceased, do: "bg-base-300 border-base-300", else: "badge-success")
            ]}
            title={if(person.deceased, do: "Deceased")}
          >
          </span>
          <div class="w-10 h-10 rounded-full overflow-hidden bg-base-200 flex items-center justify-center">
            <%= if person.photo && person.photo_status == "processed" do %>
              <img
                src={Ancestry.Uploaders.PersonPhoto.url({person.photo, person}, :thumbnail)}
                alt={Ancestry.People.Person.display_name(person)}
                class="w-full h-full object-cover"
              />
            <% else %>
              <.icon name="hero-user" class="w-5 h-5 text-base-content/30" />
            <% end %>
          </div>
        </div>
      </div>

      <%!-- Name cell --%>
      <div class="px-3 py-2.5 min-w-0 font-medium text-base-content truncate">
        <%= if person.surname && person.surname != "" do %>
          {person.surname}, {person.given_name}
        <% else %>
          {person.given_name}
        <% end %>
      </div>

      <%!-- Estimated Age cell --%>
      <div class="px-3 py-2.5 text-sm text-base-content/60">
        <%= case estimated_age(person) do %>
          <% nil -> %>
            &mdash;
          <% age -> %>
            ~{age}
        <% end %>
      </div>

      <%!-- Lifespan cell --%>
      <div class="px-3 py-2.5 text-sm text-base-content/60">
        <%= cond do %>
          <% person.birth_year && person.death_year -> %>
            b. {person.birth_year} &ndash; d. {person.death_year}
          <% person.birth_year -> %>
            b. {person.birth_year}
          <% person.death_year -> %>
            d. {person.death_year}
          <% true -> %>
            &mdash;
        <% end %>
      </div>

      <%!-- Links cell --%>
      <div class="px-3 py-2.5 text-sm" {test_id("people-links-#{person.id}")}>
        <%= if rel_count > 0 do %>
          <span class="text-base-content/60">{rel_count}</span>
        <% else %>
          <.icon name="hero-exclamation-triangle" class="w-4 h-4 text-warning" />
        <% end %>
      </div>

      <%!-- Actions cell --%>
      <div class="px-3 py-2.5 text-right">
        <%= unless @editing do %>
          <button
            phx-click="request_remove_one"
            phx-value-id={person.id}
            class="btn btn-ghost btn-xs btn-circle text-base-content/40 hover:text-error"
            title="Remove from family"
            {test_id("people-unlink-#{person.id}")}
          >
            <.icon name="hero-link-slash" class="w-4 h-4" />
          </button>
        <% end %>
      </div>
    </div>
  </div>
</div>
```

- [ ] **Step 5: Verify it compiles and renders**

Run: `mix compile --warnings-as-errors`
Expected: Compiles clean.

Then start the dev server and manually verify the page at `/families/:family_id/people`:
Run: `iex -S mix phx.server`
Expected: The grid table renders with header, zebra striping, all 6 columns, and the unlinked chip.

- [ ] **Step 6: Commit**

```bash
git add lib/web/live/people_live/index.html.heex
git commit -m "feat: rewrite people index template as CSS Grid table"
```

---

### Task 5: Update existing E2E tests

**Files:**
- Modify: `test/user_flows/manage_people_test.exs`

The existing tests reference markup that has changed. Update selectors and assertions.

- [ ] **Step 1: Update "view people table with correct data" test**

The test currently asserts on `text: "deceased"` and `text: "not connected"`. These are gone — deceased status is now shown via the indicator dot, and 0-link people show a warning icon. Update:

```elixir
test "view people table with correct data", %{conn: conn, family: family, alice: alice, diana: diana} do
  conn =
    conn
    |> visit(~p"/families/#{family.id}/people")
    |> wait_liveview()

  # Verify table shows all 4 people
  conn
  |> assert_has(test_id("people-table"))
  |> assert_has(test_id("people-table"), text: "Smith, Alice")
  |> assert_has(test_id("people-table"), text: "Smith, Bob")
  |> assert_has(test_id("people-table"), text: "Jones, Charlie")
  |> assert_has(test_id("people-table"), text: "Williams, Diana")

  # Verify Diana (0 relationships) shows warning icon
  conn
  |> assert_has(test_id("people-links-#{diana.id}") <> " .hero-exclamation-triangle")

  # Verify lifespan for Alice (deceased with both years)
  conn
  |> assert_has(test_id("people-table"), text: "b. 1950")
  |> assert_has(test_id("people-table"), text: "d. 2020")

  # Verify deceased indicator has title attribute
  conn
  |> assert_has(test_id("people-row-#{alice.id}") <> " .indicator-item[title='Deceased']")
end
```

- [ ] **Step 2: Verify existing tests still pass**

Run: `mix test test/user_flows/manage_people_test.exs`
Expected: All tests pass. If any fail due to changed selectors, fix them.

- [ ] **Step 3: Commit**

```bash
git add test/user_flows/manage_people_test.exs
git commit -m "test: update existing people E2E tests for grid table markup"
```

---

### Task 6: Add new E2E tests for unlinked filter, per-row unlink, and age display

**Files:**
- Modify: `test/user_flows/manage_people_test.exs`

- [ ] **Step 1: Add test for unlinked filter chip**

```elixir
# Given a family with people (some linked, some not)
# When the user clicks the "Unlinked" chip
# Then only people with 0 relationships are shown
# When the user clicks the chip again
# Then all people are shown again
test "unlinked chip filters to people with 0 relationships", %{
  conn: conn,
  family: family,
  diana: diana
} do
  conn =
    conn
    |> visit(~p"/families/#{family.id}/people")
    |> wait_liveview()

  # Click the Unlinked chip
  conn =
    conn
    |> click(test_id("people-unlinked-chip"))
    |> wait_liveview()

  # Only Diana (0 relationships) should be visible
  conn
  |> assert_has(test_id("people-table"), text: "Williams, Diana", timeout: 5_000)
  |> refute_has(test_id("people-table"), text: "Smith, Alice")
  |> refute_has(test_id("people-table"), text: "Smith, Bob")
  |> refute_has(test_id("people-table"), text: "Jones, Charlie")

  # Click again to deactivate
  conn =
    conn
    |> click(test_id("people-unlinked-chip"))
    |> wait_liveview()

  # All people should be visible again
  conn
  |> assert_has(test_id("people-table"), text: "Smith, Alice", timeout: 5_000)
  |> assert_has(test_id("people-table"), text: "Williams, Diana")
end
```

- [ ] **Step 2: Add test for unlinked filter composing with text search**

```elixir
# Given a family where Diana (unlinked) has surname "Williams"
# When the user activates the unlinked chip AND types a non-matching search
# Then no results are shown
# When the user clears the search and types a matching search
# Then only Diana is shown
test "unlinked filter composes with text search", %{
  conn: conn,
  family: family
} do
  conn =
    conn
    |> visit(~p"/families/#{family.id}/people")
    |> wait_liveview()

  # Activate unlinked filter
  conn =
    conn
    |> click(test_id("people-unlinked-chip"))
    |> wait_liveview()
    |> assert_has(test_id("people-table"), text: "Williams, Diana", timeout: 5_000)

  # Search for "Smith" — no unlinked person has surname Smith
  conn = PhoenixTest.Playwright.type(conn, test_id("people-search") <> " input", "Smith")

  conn
  |> refute_has(test_id("people-table"), text: "Williams, Diana", timeout: 5_000)
  |> refute_has(test_id("people-table"), text: "Smith, Alice")
end
```

- [ ] **Step 3: Add test for per-row unlink button**

```elixir
# Given a family with people
# When the user clicks the unlink icon on a person's row
# Then the confirmation modal appears
# When the user confirms
# Then that person is removed from the family
test "per-row unlink button removes person from family", %{
  conn: conn,
  family: family,
  diana: diana
} do
  conn =
    conn
    |> visit(~p"/families/#{family.id}/people")
    |> wait_liveview()

  # Click the unlink button on Diana's row
  conn =
    conn
    |> click(test_id("people-unlink-#{diana.id}"))
    |> wait_liveview()

  # Confirmation modal should appear
  conn =
    conn
    |> assert_has(test_id("people-confirm-remove-modal"))

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

- [ ] **Step 4: Add test for estimated age display**

Note: Bob's age is computed dynamically to avoid test breakage across years.

```elixir
# Given a family with people with different birth/death years
# When the user views the people table
# Then estimated ages are displayed correctly
test "estimated age displays correctly", %{conn: conn, family: family} do
  conn =
    conn
    |> visit(~p"/families/#{family.id}/people")
    |> wait_liveview()

  # Alice: deceased, birth_year: 1950, death_year: 2020 → ~70 (stable)
  conn
  |> assert_has(test_id("people-table"), text: "~70")

  # Bob: alive, birth_year: 1955 → dynamic age
  expected_bob_age = Date.utc_today().year - 1955

  conn
  |> assert_has(test_id("people-table"), text: "~#{expected_bob_age}")
end
```

- [ ] **Step 5: Add test for unlink button hidden in edit mode**

```elixir
# Given the people table in normal mode
# When the user enters edit mode
# Then the per-row unlink buttons are hidden
# When the user exits edit mode
# Then the unlink buttons reappear
test "per-row unlink buttons hidden in edit mode", %{
  conn: conn,
  family: family,
  diana: diana
} do
  conn =
    conn
    |> visit(~p"/families/#{family.id}/people")
    |> wait_liveview()

  # Unlink button visible in normal mode
  conn
  |> assert_has(test_id("people-unlink-#{diana.id}"))

  # Enter edit mode
  conn =
    conn
    |> click(test_id("people-edit-btn"))
    |> wait_liveview()

  # Unlink button should be hidden
  conn
  |> refute_has(test_id("people-unlink-#{diana.id}"))

  # Exit edit mode
  conn =
    conn
    |> click(test_id("people-edit-btn"))
    |> wait_liveview()

  # Unlink button should be visible again
  conn
  |> assert_has(test_id("people-unlink-#{diana.id}"))
end
```

- [ ] **Step 6: Run all tests**

Run: `mix test test/user_flows/manage_people_test.exs`
Expected: All tests pass.

- [ ] **Step 7: Commit**

```bash
git add test/user_flows/manage_people_test.exs
git commit -m "test: add E2E tests for unlinked filter, per-row unlink, age display"
```

---

### Task 7: Final verification

- [ ] **Step 1: Run full test suite**

Run: `mix test`
Expected: All tests pass.

- [ ] **Step 2: Run precommit checks**

Run: `mix precommit`
Expected: Compilation (warnings-as-errors), formatting, and tests all pass.

- [ ] **Step 3: Visual verification**

Start the dev server and manually verify at `/families/:family_id/people`:
- Grid table renders with all 6 columns
- Header labels are visible
- Zebra striping alternates rows
- Photo indicator dot: green for alive, gray for deceased, tooltip on deceased
- Estimated age shows `~N` or `—`
- Lifespan shows `b. YYYY – d. YYYY` variants
- Links column: number for >0, yellow warning icon for 0
- Unlinked chip toggles filter
- Unlinked chip + search compose correctly
- Per-row unlink button shows confirmation modal
- Edit mode: checkbox column prepended, unlink buttons hidden
- Bulk select + remove still works

- [ ] **Step 4: Commit any fixes**

If any fixes were needed, commit them:
```bash
git add -A
git commit -m "fix: address visual/functional issues from manual verification"
```
