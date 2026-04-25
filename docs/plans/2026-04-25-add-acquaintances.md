# Add Acquaintances — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow creating and linking acquaintances from photo tagging, memory @-mentions, and the photo lightbox sidebar via a reusable QuickPersonModal component.

**Architecture:** Six changes layered bottom-up: (1) remove `kind` filter from search functions, (2) allow nil coordinates in PhotoPerson, (3) make tag_person_in_photo an upsert, (4) build QuickPersonModal LiveComponent, (5) wire it into photo tagging + sidebar + memory mentions, (6) replace the family graph quick-create with it.

**Tech Stack:** Elixir/Phoenix LiveView, Ecto, JavaScript hooks (PhotoTagger, TrixEditor), Oban (photo processing), Waffle (uploads), gettext (i18n)

**Design spec:** `docs/plans/2026-04-25-add-acquaintances-design.md`

---

### Task 1: Remove `kind` Filter from Search Functions

**Files:**
- Modify: `lib/ancestry/people.ex:242-269`
- Test: `test/ancestry/people_test.exs`

- [ ] **Step 1: Write tests for acquaintance search inclusion**

In `test/ancestry/people_test.exs`, add tests verifying that `search_all_people/2` and `search_all_people/3` return acquaintances. You'll need a helper to create an acquaintance person (use `People.create_person_without_family/2` with `%{"given_name" => "...", "kind" => "acquaintance"}`).

```elixir
describe "search_all_people/2 includes acquaintances" do
  test "returns both family members and acquaintances", %{org: org, family: family} do
    {:ok, %{person: family_person}} = People.create_person(family, %{"given_name" => "Carlos", "surname" => "Test"})
    {:ok, acquaintance} = People.create_person_without_family(org, %{"given_name" => "Carmen", "surname" => "Test", "kind" => "acquaintance"})

    results = People.search_all_people("Car", org.id)
    result_ids = Enum.map(results, & &1.id)

    assert family_person.id in result_ids
    assert acquaintance.id in result_ids
  end
end
```

Add a similar test for the 3-arity version with `exclude_person_id`.

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ancestry/people_test.exs --trace`
Expected: FAIL — acquaintance not in results because of `kind == "family_member"` filter.

- [ ] **Step 3: Remove the `kind` filter**

In `lib/ancestry/people.ex`, remove the `where: p.kind == "family_member"` line from both functions:

**search_all_people/2** (line 248): delete `where: p.kind == "family_member",`

**search_all_people/3** (line 263): delete `where: p.kind == "family_member",`

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/ancestry/people_test.exs --trace`
Expected: PASS

- [ ] **Step 5: Verify memory mentions handler**

Read `lib/web/live/memory_live/form.ex:167-180`. The `search_mentions` handler calls `People.search_all_people(query, org_id)` — no additional filter. The fix in Step 3 covers this path too. No changes needed in `form.ex`.

- [ ] **Step 6: Commit**

```bash
git add lib/ancestry/people.ex test/ancestry/people_test.exs
git commit -m "Include acquaintances in people search results

Remove kind == family_member filter from search_all_people/2 and /3
so acquaintances appear in photo tagging and memory mention searches."
```

---

### Task 2: Allow Nil Coordinates in PhotoPerson + Upsert

**Files:**
- Modify: `lib/ancestry/galleries/photo_person.ex:15-24`
- Modify: `lib/ancestry/galleries.ex:78-82`
- Modify: `assets/js/photo_tagger.js` (renderCircles function)
- Test: `test/ancestry/galleries_test.exs`

- [ ] **Step 1: Write tests for nil coordinates and upsert**

In `test/ancestry/galleries_test.exs`, add:

```elixir
describe "tag_person_in_photo/4 with nil coordinates" do
  test "creates a photo_person with nil x and y", %{photo: photo, person: person} do
    assert {:ok, pp} = Galleries.tag_person_in_photo(photo.id, person.id, nil, nil)
    assert pp.x == nil
    assert pp.y == nil
  end

  test "upserts coordinates on an existing nil-coordinate tag", %{photo: photo, person: person} do
    {:ok, _} = Galleries.tag_person_in_photo(photo.id, person.id, nil, nil)
    {:ok, pp} = Galleries.tag_person_in_photo(photo.id, person.id, 0.5, 0.5)
    assert pp.x == 0.5
    assert pp.y == 0.5
    # Only one record exists
    assert length(Galleries.list_photo_people(photo.id)) == 1
  end

  test "upserts coordinates on an existing positioned tag", %{photo: photo, person: person} do
    {:ok, _} = Galleries.tag_person_in_photo(photo.id, person.id, 0.3, 0.3)
    {:ok, pp} = Galleries.tag_person_in_photo(photo.id, person.id, 0.7, 0.8)
    assert pp.x == 0.7
    assert pp.y == 0.8
    assert length(Galleries.list_photo_people(photo.id)) == 1
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ancestry/galleries_test.exs --trace`
Expected: FAIL — nil coordinates fail `validate_required`, and duplicate insert fails unique constraint.

- [ ] **Step 3: Update PhotoPerson changeset**

In `lib/ancestry/galleries/photo_person.ex`, replace the changeset:

```elixir
def changeset(photo_person, attrs) do
  photo_person
  |> cast(attrs, [:x, :y])
  |> maybe_validate_coordinate_range(:x)
  |> maybe_validate_coordinate_range(:y)
  |> foreign_key_constraint(:photo_id)
  |> foreign_key_constraint(:person_id)
  |> unique_constraint([:photo_id, :person_id])
end

defp maybe_validate_coordinate_range(changeset, field) do
  case get_field(changeset, field) do
    nil -> changeset
    _ -> validate_number(changeset, field, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
  end
end
```

- [ ] **Step 4: Update tag_person_in_photo to upsert**

In `lib/ancestry/galleries.ex`, replace `tag_person_in_photo/4`:

```elixir
def tag_person_in_photo(photo_id, person_id, x, y) do
  %PhotoPerson{photo_id: photo_id, person_id: person_id}
  |> PhotoPerson.changeset(%{x: x, y: y})
  |> Repo.insert(
    on_conflict: {:replace, [:x, :y]},
    conflict_target: [:photo_id, :person_id],
    returning: true
  )
end
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/ancestry/galleries_test.exs --trace`
Expected: PASS. Also verify existing coordinate-based tests still pass.

- [ ] **Step 6: Update PhotoTagger JS to skip nil-coordinate circles**

In `assets/js/photo_tagger.js`, find the `renderCircles` function (around line 225). Add a filter at the top to skip entries with null coordinates:

```javascript
renderCircles(photoPeople) {
  // ... existing container setup code ...

  photoPeople
    .filter(pp => pp.x != null && pp.y != null)
    .forEach(pp => {
      // ... existing circle rendering code ...
    })
}
```

- [ ] **Step 7: Run all tests**

Run: `mix test`
Expected: All pass.

- [ ] **Step 8: Commit**

```bash
git add lib/ancestry/galleries/photo_person.ex lib/ancestry/galleries.ex assets/js/photo_tagger.js test/ancestry/galleries_test.exs
git commit -m "Allow nil coordinates in PhotoPerson for reference links

- Remove validate_required for x/y, make range validation conditional
- Change tag_person_in_photo to upsert (on_conflict replace x/y)
- Skip rendering tag circles for nil-coordinate photo_people in JS"
```

---

### Task 3: Build QuickPersonModal LiveComponent

**Files:**
- Create: `lib/web/live/shared/quick_person_modal.ex`
- Test: `test/web/live/shared/quick_person_modal_test.exs`

- [ ] **Step 1: Write component test**

Create `test/web/live/shared/quick_person_modal_test.exs`. Test that the component renders the expected fields and that the acquaintance checkbox is conditionally shown. Use `Phoenix.LiveViewTest`.

```elixir
defmodule Web.Shared.QuickPersonModalTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest

  # Test that the component renders given_name, surname, gender, birth date fields
  # Test that acquaintance checkbox is shown when show_acquaintance is true
  # Test that acquaintance checkbox is hidden when show_acquaintance is false
  # Test that prefill_name populates given_name field
  # Test that form validation shows error when given_name is empty
end
```

Write LiveView tests using a test LiveView wrapper that mounts the component and handles messages. Follow the pattern used by other component tests in the project.

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/web/live/shared/quick_person_modal_test.exs --trace`
Expected: FAIL — module does not exist.

- [ ] **Step 3: Create the QuickPersonModal component**

Create `lib/web/live/shared/quick_person_modal.ex`:

```elixir
defmodule Web.Shared.QuickPersonModal do
  use Web, :live_component

  alias Ancestry.People
  alias Ancestry.People.Person

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> allow_upload(:photo,
       accept: ~w(.jpg .jpeg .png .webp .tif .tiff),
       max_entries: 1,
       max_file_size: 20 * 1_048_576
     )}
  end

  @impl true
  def update(assigns, socket) do
    changeset =
      %Person{}
      |> People.change_person(%{
        "given_name" => assigns[:prefill_name] || "",
        "kind" => "family_member"
      })

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:show_acquaintance, fn -> true end)
     |> assign_new(:family_id, fn -> nil end)
     |> assign_new(:prefill_name, fn -> nil end)
     |> assign(:form, to_form(changeset, as: :person))}
  end

  @impl true
  def render(assigns) do
    # Render a <.modal> with:
    # - Photo upload (optional) — circular dashed border placeholder, live_file_input
    # - Given name input (required)
    # - Surname input
    # - Gender radio buttons (Female / Male / Other)
    # - Birth date (day dropdown 1-31, month dropdown 1-12, year text input)
    # - Acquaintance checkbox (only if @show_acquaintance is true)
    #   - hidden input value="family_member" + checkbox value="acquaintance"
    # - Cancel and Create buttons
    # Use <.form for={@form} phx-target={@myself} phx-change="validate" phx-submit="save">
    # Use <.input> components from core_components where possible
    # Follow the styling patterns in PersonFormComponent
  end

  @impl true
  def handle_event("validate", %{"person" => params}, socket) do
    changeset =
      %Person{}
      |> People.change_person(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset, as: :person))}
  end

  @impl true
  def handle_event("save", %{"person" => params}, socket) do
    case create_person(socket.assigns, params) do
      {:ok, person} ->
        person = maybe_process_photo(socket, person)
        send(self(), {:person_created, person})
        {:noreply, socket}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset, as: :person))}
    end
  end

  @impl true
  def handle_event("cancel", _, socket) do
    send(self(), {:quick_person_cancelled})
    {:noreply, socket}
  end

  defp create_person(%{family_id: family_id, organization_id: org_id}, params) when not is_nil(family_id) do
    family = Ancestry.Families.get_family!(family_id)
    People.create_person(family, params)
  end

  defp create_person(%{organization_id: org_id}, params) do
    org = Ancestry.Organizations.get_organization!(org_id)
    People.create_person_without_family(org, params)
  end

  defp maybe_process_photo(socket, person) do
    uploaded =
      consume_uploaded_entries(socket, :photo, fn %{path: tmp_path}, entry ->
        uuid = Ecto.UUID.generate()
        ext = Path.extname(entry.client_name)
        dest_key = Path.join(["uploads", "originals", uuid, "photo#{ext}"])
        original_path = Ancestry.Storage.store_original(tmp_path, dest_key)
        {:ok, original_path}
      end)

    case uploaded do
      [original_path] ->
        People.update_photo_pending(person, original_path)
        person

      [] ->
        person
    end
  end
end
```

Note: the `render/1` function body is intentionally left as a guide — the implementer should write the full HEEx template following the mockup in the design spec and the styling patterns from `PersonFormComponent` (`lib/web/live/shared/person_form_component.html.heex`). Key reference:
- Photo upload: lines 11-71
- Name inputs: lines 74-123
- Gender radios: lines 135-172
- Birth date: lines 174-215
- Acquaintance checkbox: lines 234-255

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/web/live/shared/quick_person_modal_test.exs --trace`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/web/live/shared/quick_person_modal.ex test/web/live/shared/quick_person_modal_test.exs
git commit -m "Add QuickPersonModal LiveComponent

Reusable modal for quick person creation with photo upload, name,
gender, birth date, and conditional acquaintance checkbox.
Sends {:person_created, person} to parent on success."
```

---

### Task 4: Add "Create Person" to Photo Tag Search

**Files:**
- Modify: `assets/js/photo_tagger.js:164-223` (renderSearchResults)
- Modify: `lib/web/components/photo_gallery.ex` (add `data-photo-id` to PhotoTagger hook element)
- Modify: `lib/web/photo_interactions.ex` (make `push_photo_people/1` public)
- Modify: `lib/web/live/gallery_live/show.ex:175-194`
- Modify: `lib/web/live/gallery_live/show.html.heex`
- Modify: `lib/web/live/person_live/show.ex` (if it has photo tagging)
- Test: `test/user_flows/link_people_in_photos_test.exs`

- [ ] **Step 1a: Add `data-photo-id` to PhotoTagger hook element**

In `lib/web/components/photo_gallery.ex`, find the `<img>` element with `phx-hook="PhotoTagger"` (around line 195-201). Add `data-photo-id={@selected_photo.id}` so the JS hook can send the photo ID with events.

- [ ] **Step 1b: Make `push_photo_people/1` public in PhotoInteractions**

In `lib/web/photo_interactions.ex`, change `defp push_photo_people(socket)` to `def push_photo_people(socket)`. This is needed because the `handle_info({:person_created, ...})` handler in the parent LiveView needs to call it after tagging.

- [ ] **Step 2: Add "Create person" button to PhotoTagger JS**

In `assets/js/photo_tagger.js`, modify `renderSearchResults`. After the existing `results.forEach(...)` loop, add a "Create person" button at the bottom if there's a search query:

```javascript
// After results.forEach block, before the closing of renderSearchResults:
const input = this.popoverContainer.querySelector("#tag-search-input")
const query = input ? input.value.trim() : ""

if (query.length >= 1) {
  const divider = document.createElement("div")
  divider.className = "border-t border-white/10 mt-1 pt-1"

  const createBtn = document.createElement("button")
  createBtn.className = "flex items-center gap-2 w-full px-2 py-1.5 rounded-lg hover:bg-emerald-900/40 transition-colors text-left border border-dashed border-emerald-500/40"

  const plusIcon = document.createElement("div")
  plusIcon.className = "w-6 h-6 rounded-full bg-emerald-900 flex items-center justify-center shrink-0 text-emerald-400 text-sm font-bold"
  plusIcon.textContent = "+"
  createBtn.appendChild(plusIcon)

  const label = document.createElement("span")
  label.className = "text-sm text-emerald-400 truncate"
  const truncated = query.length > 20 ? query.substring(0, 20) + "..." : query
  label.textContent = `Create "${truncated}"`
  createBtn.appendChild(label)

  createBtn.addEventListener("click", (e) => {
    e.stopPropagation()
    if (this.pendingClick) {
      this.pushEvent("create_person_from_tag", {
        x: this.pendingClick.x,
        y: this.pendingClick.y,
        query: query,
        photo_id: this.el.dataset.photoId
      })
      this.hidePopover()
    }
  })

  divider.appendChild(createBtn)
  container.appendChild(divider)
}
```

- [ ] **Step 3: Add event handler in GalleryLive.Show**

In `lib/web/live/gallery_live/show.ex`, add after the existing `search_people_for_tag` handler (around line 194):

```elixir
def handle_event("create_person_from_tag", %{"x" => x, "y" => y, "query" => query, "photo_id" => photo_id}, socket) do
  {:noreply,
   socket
   |> assign(:pending_tag, %{x: x, y: y, photo_id: String.to_integer(photo_id)})
   |> assign(:show_quick_person_modal, true)
   |> assign(:quick_person_prefill, query)}
end
```

Add the `handle_info` for `{:person_created, person}`:

```elixir
def handle_info({:person_created, person}, socket) do
  socket =
    case socket.assigns[:pending_tag] do
      %{x: x, y: y, photo_id: photo_id} ->
        Galleries.tag_person_in_photo(photo_id, person.id, x, y)

        # Only refresh sidebar if the user is still viewing the same photo
        if socket.assigns.selected_photo && socket.assigns.selected_photo.id == photo_id do
          socket
          |> assign(:photo_people, Galleries.list_photo_people(photo_id))
          |> PhotoInteractions.push_photo_people()
        else
          socket
        end

      nil ->
        socket
    end

  {:noreply,
   socket
   |> assign(:pending_tag, nil)
   |> assign(:show_quick_person_modal, false)
   |> assign(:quick_person_prefill, nil)}
end

def handle_info({:quick_person_cancelled}, socket) do
  {:noreply,
   socket
   |> assign(:pending_tag, nil)
   |> assign(:show_quick_person_modal, false)
   |> assign(:quick_person_prefill, nil)}
end
```

- [ ] **Step 4: Add QuickPersonModal to GalleryLive.Show template**

In `lib/web/live/gallery_live/show.html.heex`, add the modal (conditionally rendered):

```heex
<.live_component
  :if={@show_quick_person_modal}
  module={Web.Shared.QuickPersonModal}
  id="quick-person-modal"
  show_acquaintance={true}
  organization_id={@current_scope.organization.id}
  prefill_name={@quick_person_prefill}
/>
```

Initialize the assigns in `mount` or wherever socket assigns are set up:
- `show_quick_person_modal: false`
- `pending_tag: nil`
- `quick_person_prefill: nil`

- [ ] **Step 5: Add E2E test for create-person-from-photo-tag flow**

In `test/user_flows/link_people_in_photos_test.exs`, add a test:

```elixir
test "creates a new person from photo tag search and auto-tags", %{conn: conn, ...} do
  # Navigate to gallery with a processed photo
  # Open lightbox
  # Click on photo (triggers tag popover)
  # Type a name that doesn't exist
  # Click "Create" button
  # Fill in the quick person modal (given_name at minimum)
  # Submit
  # Verify person appears in the People sidebar
end
```

- [ ] **Step 6: Run tests**

Run: `mix test test/user_flows/link_people_in_photos_test.exs --trace`
Expected: PASS

- [ ] **Step 7: Apply the same changes to PersonLive.Show**

Check `lib/web/live/person_live/show.ex` — if it uses `PhotoInteractions` and handles `tag_person` / `search_people_for_tag` events, add the same `create_person_from_tag` handler, `handle_info` callbacks, assigns, and template changes. The code is identical since both delegate to `PhotoInteractions`.

- [ ] **Step 8: Commit**

```bash
git add assets/js/photo_tagger.js lib/web/components/photo_gallery.ex lib/web/photo_interactions.ex lib/web/live/gallery_live/show.ex lib/web/live/gallery_live/show.html.heex lib/web/live/person_live/show.ex test/user_flows/link_people_in_photos_test.exs
git commit -m "Add 'Create person' option to photo tag search

When tagging a photo, a 'Create person' button appears at the bottom
of search results. Clicking it opens QuickPersonModal and auto-tags
the new person at the clicked coordinates."
```

---

### Task 5: Add "Link Person" to Photo Lightbox Sidebar

**Files:**
- Modify: `lib/web/components/photo_gallery.ex:234-315`
- Modify: `lib/web/photo_interactions.ex`
- Modify: `lib/web/live/gallery_live/show.ex`
- Modify: `lib/web/live/gallery_live/show.html.heex`
- Test: `test/user_flows/link_people_in_photos_test.exs`

- [ ] **Step 1: Add sidebar search UI to photo_gallery.ex**

In `lib/web/components/photo_gallery.ex`, after the People list (around line 315), add the "Link person" button and expandable inline search. This requires new assigns on the lightbox component:
- `@linking_person` (boolean) — whether the inline search is expanded
- `@link_search_query` (string) — current search text
- `@link_search_results` (list) — search results

```heex
<%!-- After the photo-person-list div, before the closing of the People card --%>
<div class="mt-1 px-1">
  <%= if @linking_person do %>
    <%!-- Inline search --%>
    <div class="space-y-2">
      <div class="relative">
        <input
          type="text"
          value={@link_search_query}
          placeholder={gettext("Search people...")}
          phx-keyup="link_person_search"
          phx-debounce="300"
          class="w-full bg-white/[0.08] border border-white/20 rounded-lg px-3 py-2 text-sm text-white placeholder-white/40 focus:outline-none focus:border-white/40"
          autofocus
        />
        <button
          phx-click="cancel_link_person"
          class="absolute right-2 top-1/2 -translate-y-1/2 text-white/40 hover:text-white/70"
        >
          <.icon name="hero-x-mark" class="w-4 h-4" />
        </button>
      </div>

      <div class="max-h-36 overflow-y-auto flex flex-col gap-0.5">
        <%= for person <- @link_search_results do %>
          <button
            phx-click="link_existing_person"
            phx-value-person-id={person.id}
            class="flex items-center gap-2 w-full px-2 py-1.5 rounded-lg hover:bg-white/[0.08] transition-colors text-left"
          >
            <%!-- Person avatar + name (same pattern as tagged people list) --%>
          </button>
        <% end %>

        <%!-- "Create person" option --%>
        <%= if String.length(@link_search_query || "") >= 1 do %>
          <div class="border-t border-white/10 mt-1 pt-1">
            <button
              phx-click="create_person_from_link"
              phx-value-query={@link_search_query}
              class="flex items-center gap-2 w-full px-2 py-1.5 rounded-lg hover:bg-emerald-900/40 transition-colors text-left border border-dashed border-emerald-500/40"
            >
              <div class="w-6 h-6 rounded-full bg-emerald-900 flex items-center justify-center shrink-0 text-emerald-400 text-sm font-bold">+</div>
              <span class="text-sm text-emerald-400 truncate">
                {gettext("Create \"%{query}\"...", query: String.slice(@link_search_query, 0..19))}
              </span>
            </button>
          </div>
        <% end %>
      </div>
    </div>
  <% else %>
    <button
      phx-click="start_link_person"
      class="w-full py-2 rounded-lg border border-dashed border-white/20 text-white/50 hover:text-white/70 hover:border-white/40 transition-colors text-sm flex items-center justify-center gap-1.5"
    >
      <span class="text-base">+</span> {gettext("Link person")}
    </button>
  <% end %>
</div>

<p :if={!@linking_person} class="text-center text-white/30 text-[11px] mt-1.5 px-1 hidden lg:block">
  {gettext("Click on the photo to tag with position")}
</p>
```

- [ ] **Step 2: Add event handlers for sidebar link flow**

In `lib/web/photo_interactions.ex`, add helper functions:

```elixir
def start_link_person(socket) do
  assign(socket, linking_person: true, link_search_query: "", link_search_results: [])
end

def cancel_link_person(socket) do
  assign(socket, linking_person: false, link_search_query: "", link_search_results: [])
end

def search_link_person(socket, query) do
  results =
    if String.length(query) >= 2 do
      tagged_ids = Enum.map(socket.assigns.photo_people, & &1.person_id)

      Ancestry.People.search_all_people(query, socket.assigns.current_scope.organization.id)
      |> Enum.reject(fn p -> p.id in tagged_ids end)
    else
      []
    end

  assign(socket, link_search_query: query, link_search_results: results)
end

def link_existing_person(socket, person_id) do
  photo = socket.assigns.selected_photo

  Galleries.tag_person_in_photo(photo.id, String.to_integer(person_id), nil, nil)

  socket
  |> assign(:photo_people, Galleries.list_photo_people(photo.id))
  |> cancel_link_person()
  |> push_photo_people()
end
```

In `lib/web/live/gallery_live/show.ex`, add event handlers that delegate to these:

```elixir
def handle_event("start_link_person", _, socket) do
  {:noreply, PhotoInteractions.start_link_person(socket)}
end

def handle_event("cancel_link_person", _, socket) do
  {:noreply, PhotoInteractions.cancel_link_person(socket)}
end

def handle_event("link_person_search", %{"value" => query}, socket) do
  {:noreply, PhotoInteractions.search_link_person(socket, query)}
end

def handle_event("link_existing_person", %{"person-id" => person_id}, socket) do
  {:noreply, PhotoInteractions.link_existing_person(socket, person_id)}
end

def handle_event("create_person_from_link", %{"query" => query}, socket) do
  {:noreply,
   socket
   |> assign(:pending_tag, %{x: nil, y: nil, photo_id: socket.assigns.selected_photo.id})
   |> assign(:show_quick_person_modal, true)
   |> assign(:quick_person_prefill, query)
   |> PhotoInteractions.cancel_link_person()}
end
```

Initialize assigns in mount: `linking_person: false, link_search_query: "", link_search_results: []`.

Update the existing `handle_info({:person_created, person})` from Task 4 — it already handles `pending_tag` with nil coordinates, which covers this case.

- [ ] **Step 3: Pass new assigns to lightbox component**

In `lib/web/components/photo_gallery.ex`, add `attr` declarations to the `lightbox/1` function:

```elixir
attr :linking_person, :boolean, default: false
attr :link_search_query, :string, default: ""
attr :link_search_results, :list, default: []
```

In the template where `lightbox()` is called (in `show.html.heex`), pass the new assigns:

```heex
<.lightbox
  ...existing assigns...
  linking_person={@linking_person}
  link_search_query={@link_search_query}
  link_search_results={@link_search_results}
/>
```

- [ ] **Step 4: Add E2E test for link-person-from-sidebar flow**

In `test/user_flows/link_people_in_photos_test.exs`, add:

```elixir
test "links an existing person from sidebar without clicking photo", %{conn: conn, ...} do
  # Navigate to gallery, open lightbox
  # Click "Link person" button
  # Type name of existing person
  # Click on the person in results
  # Verify person appears in People sidebar
  # Verify no tag circle rendered (nil coordinates)
end

test "creates and links a new person from sidebar", %{conn: conn, ...} do
  # Navigate to gallery, open lightbox
  # Click "Link person" button
  # Type name that doesn't exist
  # Click "Create" button
  # Fill in QuickPersonModal
  # Submit
  # Verify new person appears in People sidebar
end
```

- [ ] **Step 5: Run tests**

Run: `mix test test/user_flows/link_people_in_photos_test.exs --trace`
Expected: PASS

- [ ] **Step 6: Apply same changes to PersonLive.Show**

Add the same event handlers and template changes to `PersonLive.Show` if it has a lightbox.

- [ ] **Step 7: Commit**

```bash
git add lib/web/components/photo_gallery.ex lib/web/photo_interactions.ex lib/web/live/gallery_live/show.ex lib/web/live/gallery_live/show.html.heex lib/web/live/person_live/show.ex test/user_flows/link_people_in_photos_test.exs
git commit -m "Add 'Link person' to photo lightbox sidebar

Allows linking a person to a photo without clicking on the photo
(nil coordinates). Inline search in People panel with option to
create a new person via QuickPersonModal."
```

---

### Task 6: Add "Create Person" to Memory @-Mention Dropdown

**Files:**
- Modify: `assets/js/trix_editor.js:131-186`
- Modify: `lib/web/live/memory_live/form.ex:167-180`
- Modify: `lib/web/live/memory_live/form.html.heex`
- Test: `test/user_flows/memory_vault_crud_test.exs`

- [ ] **Step 1: Add "Create person" button to Trix mention dropdown**

In `assets/js/trix_editor.js`, modify `_showMentionDropdown` (line 131). After the `results.forEach(...)` loop that creates person buttons, add a "Create person" button:

```javascript
// After results.forEach block:
if (this.mentionQuery && this.mentionQuery.length >= 1) {
  const divider = document.createElement("div")
  divider.className = "border-t border-gray-200 mt-1 pt-1"

  const createBtn = document.createElement("button")
  createBtn.type = "button"
  createBtn.className = "w-full text-left px-3 py-2 text-sm hover:bg-emerald-50 text-emerald-600 flex items-center gap-2"

  const plusSpan = document.createElement("span")
  plusSpan.className = "w-5 h-5 rounded-full bg-emerald-100 flex items-center justify-center shrink-0 text-emerald-600 text-xs font-bold"
  plusSpan.textContent = "+"
  createBtn.appendChild(plusSpan)

  const label = document.createElement("span")
  const truncated = this.mentionQuery.length > 20 ? this.mentionQuery.substring(0, 20) + "..." : this.mentionQuery
  label.textContent = `Create "${truncated}"`
  createBtn.appendChild(label)

  createBtn.addEventListener("mousedown", (e) => {
    e.preventDefault()
    // Save cursor position for later insertion
    this._savedMentionStart = this.mentionStart
    this._savedMentionQuery = this.mentionQuery
    this._savedEditorPosition = this.editorEl.editor.getSelectedRange()

    this.pushEvent("create_person_from_mention", { query: this.mentionQuery })
    this._closeMentionDropdown()
  })

  divider.appendChild(createBtn)
  dropdown.appendChild(divider)
}
```

Also add a handler for the `mention_created` event pushed from the server:

```javascript
// In mounted() or constructor, add:
this.handleEvent("mention_created", ({ id, name }) => {
  // Restore cursor position
  const editor = this.editorEl.editor
  const start = this._savedMentionStart
  const query = this._savedMentionQuery

  if (start != null && query != null) {
    // Delete the @query text (start-1 for the @ symbol, through start + query.length)
    const deleteStart = start - 1
    const deleteEnd = start + query.length
    editor.setSelectedRange([deleteStart, deleteEnd])
    editor.deleteInDirection("forward")
  }

  // Insert mention attachment
  const attachment = new Trix.Attachment({
    contentType: "application/vnd.memory-mention",
    content: `<span data-person-id="${id}" class="mention">@${name}</span>`
  })
  editor.insertAttachment(attachment)

  // Cleanup
  this._savedMentionStart = null
  this._savedMentionQuery = null
  this._savedEditorPosition = null
})

this.handleEvent("mention_cancelled", () => {
  this._savedMentionStart = null
  this._savedMentionQuery = null
  this._savedEditorPosition = null
})
```

- [ ] **Step 2: Add event handlers in MemoryLive.Form**

In `lib/web/live/memory_live/form.ex`, add:

```elixir
def handle_event("create_person_from_mention", %{"query" => query}, socket) do
  {:noreply,
   socket
   |> assign(:show_quick_person_modal, true)
   |> assign(:quick_person_prefill, query)}
end

def handle_info({:person_created, person}, socket) do
  display_name = Ancestry.People.Person.display_name(person)

  # Push the mention data to JS so the Trix hook can insert the attachment.
  # The MemoryMention record is created automatically by ContentParser
  # when the memory form is saved — no need to create it here.
  socket =
    if socket.assigns[:show_quick_person_modal] do
      push_event(socket, "mention_created", %{id: person.id, name: display_name})
    else
      socket
    end

  {:noreply,
   socket
   |> assign(:show_quick_person_modal, false)
   |> assign(:quick_person_prefill, nil)}
end

def handle_info({:quick_person_cancelled}, socket) do
  socket =
    socket
    |> assign(:show_quick_person_modal, false)
    |> assign(:quick_person_prefill, nil)
    |> push_event("mention_cancelled", %{})

  {:noreply, socket}
end
```

Initialize assigns: `show_quick_person_modal: false, quick_person_prefill: nil`.

- [ ] **Step 3: Add QuickPersonModal to memory form template**

In `lib/web/live/memory_live/form.html.heex`:

```heex
<.live_component
  :if={@show_quick_person_modal}
  module={Web.Shared.QuickPersonModal}
  id="quick-person-modal"
  show_acquaintance={true}
  organization_id={@current_scope.organization.id}
  prefill_name={@quick_person_prefill}
/>
```

- [ ] **Step 4: Add E2E test**

In `test/user_flows/memory_vault_crud_test.exs`, add:

```elixir
test "creates a new person from @-mention dropdown and auto-inserts mention", %{conn: conn, ...} do
  # Navigate to memory form
  # Type @ followed by a name that doesn't exist
  # Click "Create" in the dropdown
  # Fill in QuickPersonModal
  # Submit
  # Verify mention is inserted in the editor content
end
```

- [ ] **Step 5: Run tests**

Run: `mix test test/user_flows/memory_vault_crud_test.exs --trace`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add assets/js/trix_editor.js lib/web/live/memory_live/form.ex lib/web/live/memory_live/form.html.heex test/user_flows/memory_vault_crud_test.exs
git commit -m "Add 'Create person' to memory @-mention dropdown

When typing @name in the memory editor, a 'Create person' option
appears in the dropdown. Creates the person via QuickPersonModal
and auto-inserts the mention at the cursor position."
```

---

### Task 7: Replace Family Graph Quick-Create with QuickPersonModal

**Files:**
- Modify: `lib/web/live/shared/add_relationship_component.ex:339-372, 116-141, 543-549`
- Test: `test/user_flows/` (family graph related tests)

- [ ] **Step 1: Find existing tests for AddRelationshipComponent quick-create**

Search for tests that exercise the quick-create flow in `test/user_flows/`. These tests should still pass after the change.

Run: `grep -r "quick.create\|save_person\|Create & Continue" test/`

- [ ] **Step 2: Add `show_modal_wrapper` assign to QuickPersonModal**

Back in `lib/web/live/shared/quick_person_modal.ex`, add a `show_modal_wrapper` assign (default `true`). When `true`, wrap the form in `<.modal>`. When `false`, render the form fields directly (no modal overlay). This is needed because in the family graph context, the form is embedded inside the already-open `AddRelationshipComponent` modal.

In `update/2`, add: `assign_new(:show_modal_wrapper, fn -> true end)`

In `render/1`, conditionally wrap:
```elixir
# When show_modal_wrapper is true:
<.modal id="quick-person-modal" ...>
  <%= render_form(assigns) %>
</.modal>

# When show_modal_wrapper is false:
<%= render_form(assigns) %>
```

Extract the form fields into a `render_form/1` helper function to avoid duplication.

- [ ] **Step 3: Replace `:quick_create` step rendering**

In `lib/web/live/shared/add_relationship_component.ex`, replace the `:quick_create` case (lines 339-372) with:

```elixir
<% :quick_create -> %>
  <div id="quick-create-person">
    <button
      id="add-rel-back-to-choose-from-quick-create-btn"
      phx-click="back_to_choose"
      phx-target={@myself}
      class="flex items-center gap-1 text-sm text-ds-primary/70 hover:text-ds-primary mb-4 transition-colors"
    >
      <.icon name="hero-arrow-left" class="w-4 h-4" /> {gettext("Back")}
    </button>

    <.live_component
      module={Web.Shared.QuickPersonModal}
      id="quick-person-modal-relationship"
      show_acquaintance={false}
      show_modal_wrapper={false}
      organization_id={@family.organization_id}
      family_id={@family.id}
      prefill_name={@quick_create_prefill_name}
    />
  </div>
```

Note: uses `@family.organization_id` (not `@organization.id` which doesn't exist on this component) and `show_modal_wrapper={false}` since the form is already inside the `AddRelationshipComponent` modal.

- [ ] **Step 4: Update event handling**

`QuickPersonModal` sends `{:person_created, person}` to the parent LiveView (`FamilyLive.Show`), not to `AddRelationshipComponent`. Add a `handle_info` in `FamilyLive.Show` that forwards to the component:

```elixir
# In FamilyLive.Show:
def handle_info({:person_created, person}, socket) do
  person = People.get_person!(person.id)
  send_update(Web.Shared.AddRelationshipComponent,
    id: "add-relationship",
    person_created: person
  )
  {:noreply, socket}
end
```

In `AddRelationshipComponent.update/2`, handle the forwarded message:

```elixir
# Add a clause in update/2:
def update(%{person_created: person} = assigns, socket) do
  relationship_form = build_relationship_form(socket.assigns.relationship_type, person)

  {:ok,
   socket
   |> assign(:step, :metadata)
   |> assign(:selected_person, person)
   |> assign(:relationship_form, relationship_form)}
end
```

Remove the old `save_person` and `validate_person` event handlers from `AddRelationshipComponent` (they're now handled by `QuickPersonModal`).

Remove the `create_quick_person/2` helper (lines 543-549) — creation logic is now in `QuickPersonModal`.

- [ ] **Step 5: Handle cancel**

When `{:quick_person_cancelled}` is received, forward to the component to return to `:search`:

```elixir
# In FamilyLive.Show:
def handle_info({:quick_person_cancelled}, socket) do
  send_update(Web.Shared.AddRelationshipComponent,
    id: "add-relationship",
    cancelled: true
  )
  {:noreply, socket}
end
```

In `AddRelationshipComponent.update/2`:

```elixir
def update(%{cancelled: true}, socket) do
  {:ok, assign(socket, :step, :search)}
end
```

- [ ] **Step 6: Run existing tests**

Run: `mix test test/user_flows/ --trace`
Expected: All existing tests pass (the quick-create flow should work the same from the user's perspective, just with more fields available).

- [ ] **Step 7: Add test for enhanced quick-create**

Add a test verifying the new fields (gender, birth date) work in the family graph quick-create flow.

- [ ] **Step 8: Commit**

```bash
git add lib/web/live/shared/add_relationship_component.ex lib/web/live/family_live/show.ex test/user_flows/
git commit -m "Replace family graph quick-create with QuickPersonModal

The AddRelationshipComponent's 2-field quick-create now uses
QuickPersonModal with gender, birth date, and photo upload.
Acquaintance checkbox is hidden in this context."
```

---

### Task 8: i18n — Extract and Translate New Strings

**Files:**
- Modify: `priv/gettext/es-UY/LC_MESSAGES/default.po`
- Run: `mix gettext.extract --merge`

- [ ] **Step 1: Extract gettext strings**

Run: `mix gettext.extract --merge`

- [ ] **Step 2: Add Spanish translations**

Open `priv/gettext/es-UY/LC_MESSAGES/default.po` and find the new untranslated strings. Add translations:

| English | Spanish |
|---------|---------|
| Create person | Crear persona |
| Link person | Vincular persona |
| Create "%{query}"... | Crear "%{query}"... |
| Click on the photo to tag with position | Hacé clic en la foto para etiquetar con posición |
| Search people... | Buscar personas... |
| This person is not a family member (acquaintance) | Esta persona no es familiar (conocido/a) |

- [ ] **Step 3: Commit**

```bash
git add priv/gettext/
git commit -m "Add Spanish translations for acquaintance feature strings"
```

---

### Task 9: Final Verification

- [ ] **Step 1: Run full test suite**

Run: `mix precommit`
Expected: All tests pass, no warnings, code formatted.

- [ ] **Step 2: Manual testing**

Start the dev server: `iex -S mix phx.server`

Test all flows:
1. Photo tagging search returns acquaintances
2. "Create person" in photo tag search → auto-tags
3. "Link person" in sidebar → search → link existing (nil coords)
4. "Link person" in sidebar → "Create person" → auto-links
5. Memory @-mention search returns acquaintances
6. "Create person" in @-mention dropdown → auto-inserts mention
7. Family graph quick-create has all fields, no acquaintance checkbox
8. Upgrading a reference link by clicking on the photo to place coordinates

- [ ] **Step 3: Commit any fixes**

If manual testing reveals issues, fix and commit.
