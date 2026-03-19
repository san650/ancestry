# Link People in Photos — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Allow users to tag people on gallery photos by clicking to place a marker, selecting a person from a search popover, and displaying tagged people as circles overlaid on the photo and listed in a generalized right panel.

**Architecture:** New `photo_people` join table with percentage-based coordinates. Colocated JS hook (`.PhotoTagger`) handles click-to-tag interaction with a popover. Right panel is generalized from comments-only to stacked People + Comments sections.

**Tech Stack:** Phoenix LiveView, Ecto, colocated JS hooks, Tailwind CSS

---

### Task 1: Migration and Schema — `photo_people` table

**Files:**
- Create: `lib/ancestry/galleries/photo_person.ex`
- Modify: `lib/ancestry/galleries/photo.ex:6-15` (add association)
- Modify: `lib/ancestry/people/person.ex:6-30` (add association)

**Step 1: Generate the migration**

Run: `mix ecto.gen.migration create_photo_people`

**Step 2: Write the migration**

Open the generated file in `priv/repo/migrations/*_create_photo_people.exs` and write:

```elixir
defmodule Ancestry.Repo.Migrations.CreatePhotoPeople do
  use Ecto.Migration

  def change do
    create table(:photo_people) do
      add :photo_id, references(:photos, on_delete: :delete_all), null: false
      add :person_id, references(:persons, on_delete: :delete_all), null: false
      add :x, :float, null: false
      add :y, :float, null: false

      timestamps(updated_at: false)
    end

    create index(:photo_people, [:photo_id])
    create index(:photo_people, [:person_id])
    create unique_index(:photo_people, [:photo_id, :person_id])
  end
end
```

**Step 3: Create the PhotoPerson schema**

Create `lib/ancestry/galleries/photo_person.ex`:

```elixir
defmodule Ancestry.Galleries.PhotoPerson do
  use Ecto.Schema
  import Ecto.Changeset

  schema "photo_people" do
    belongs_to :photo, Ancestry.Galleries.Photo
    belongs_to :person, Ancestry.People.Person

    field :x, :float
    field :y, :float

    timestamps(updated_at: false)
  end

  def changeset(photo_person, attrs) do
    photo_person
    |> cast(attrs, [:x, :y])
    |> validate_required([:x, :y])
    |> validate_number(:x, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:y, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> foreign_key_constraint(:photo_id)
    |> foreign_key_constraint(:person_id)
    |> unique_constraint([:photo_id, :person_id])
  end
end
```

**Step 4: Add associations to Photo schema**

In `lib/ancestry/galleries/photo.ex`, inside the schema block after `has_many :photo_comments` (line 13), add:

```elixir
has_many :photo_people, Ancestry.Galleries.PhotoPerson
has_many :people, through: [:photo_people, :person]
```

**Step 5: Add associations to Person schema**

In `lib/ancestry/people/person.ex`, inside the schema block after `many_to_many :families` (line 27), add:

```elixir
has_many :photo_people, Ancestry.Galleries.PhotoPerson
has_many :photos, through: [:photo_people, :photo]
```

**Step 6: Run migration**

Run: `mix ecto.migrate`
Expected: Migration runs successfully.

**Step 7: Commit**

```
feat: add photo_people schema and migration for tagging people in photos
```

---

### Task 2: Context functions — tag, untag, list

**Files:**
- Modify: `lib/ancestry/galleries.ex:1-69` (add new functions)
- Modify: `lib/ancestry/people.ex:93-118` (add search_all_people/1 variant)
- Test: `test/ancestry/galleries_test.exs` (add photo_people tests)

**Step 1: Write failing tests**

Add a new `describe "photo_people"` block at the end of `test/ancestry/galleries_test.exs` (before the `gallery_fixture` helper):

```elixir
describe "photo_people" do
  setup %{family: family} do
    {:ok, gallery} = Galleries.create_gallery(%{name: "Test", family_id: family.id})

    {:ok, photo} =
      Galleries.create_photo(%{
        gallery_id: gallery.id,
        original_path: "/tmp/test.jpg",
        original_filename: "test.jpg",
        content_type: "image/jpeg"
      })

    {:ok, person} =
      Ancestry.People.create_person(%{given_name: "Alice", surname: "Smith"})

    %{gallery: gallery, photo: photo, person: person}
  end

  test "tag_person_in_photo/4 creates a photo_person record", %{photo: photo, person: person} do
    assert {:ok, photo_person} = Galleries.tag_person_in_photo(photo.id, person.id, 0.5, 0.3)
    assert photo_person.photo_id == photo.id
    assert photo_person.person_id == person.id
    assert photo_person.x == 0.5
    assert photo_person.y == 0.3
  end

  test "tag_person_in_photo/4 rejects duplicate tag", %{photo: photo, person: person} do
    assert {:ok, _} = Galleries.tag_person_in_photo(photo.id, person.id, 0.5, 0.3)
    assert {:error, changeset} = Galleries.tag_person_in_photo(photo.id, person.id, 0.2, 0.8)
    assert "has already been taken" in errors_on(changeset).photo_id
  end

  test "tag_person_in_photo/4 validates coordinate bounds", %{photo: photo, person: person} do
    assert {:error, changeset} = Galleries.tag_person_in_photo(photo.id, person.id, 1.5, -0.1)
    assert errors_on(changeset).x
    assert errors_on(changeset).y
  end

  test "untag_person_from_photo/2 removes the tag", %{photo: photo, person: person} do
    {:ok, _} = Galleries.tag_person_in_photo(photo.id, person.id, 0.5, 0.3)
    assert :ok = Galleries.untag_person_from_photo(photo.id, person.id)
    assert Galleries.list_photo_people(photo.id) == []
  end

  test "untag_person_from_photo/2 is a no-op when not tagged", %{photo: photo, person: person} do
    assert :ok = Galleries.untag_person_from_photo(photo.id, person.id)
  end

  test "list_photo_people/1 returns tagged people with preloaded person", %{
    photo: photo,
    person: person
  } do
    {:ok, person2} = Ancestry.People.create_person(%{given_name: "Bob", surname: "Jones"})

    {:ok, _} = Galleries.tag_person_in_photo(photo.id, person.id, 0.5, 0.3)
    {:ok, _} = Galleries.tag_person_in_photo(photo.id, person2.id, 0.8, 0.6)

    result = Galleries.list_photo_people(photo.id)
    assert length(result) == 2
    assert Enum.all?(result, fn pp -> pp.person != nil end)
    assert hd(result).person.given_name == "Alice"
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/ancestry/galleries_test.exs`
Expected: FAIL — functions not defined.

**Step 3: Implement context functions**

Add to `lib/ancestry/galleries.ex` at the end of the module (before `end`):

```elixir
alias Ancestry.Galleries.PhotoPerson

def tag_person_in_photo(photo_id, person_id, x, y) do
  %PhotoPerson{photo_id: photo_id, person_id: person_id}
  |> PhotoPerson.changeset(%{x: x, y: y})
  |> Repo.insert()
end

def untag_person_from_photo(photo_id, person_id) do
  from(pp in PhotoPerson,
    where: pp.photo_id == ^photo_id and pp.person_id == ^person_id
  )
  |> Repo.delete_all()

  :ok
end

def list_photo_people(photo_id) do
  Repo.all(
    from pp in PhotoPerson,
      where: pp.photo_id == ^photo_id,
      order_by: [asc: pp.inserted_at, asc: pp.id],
      preload: [:person]
  )
end
```

**Step 4: Add search_all_people/1 to People context**

The existing `search_all_people/2` requires a non-nil `exclude_person_id`. Per the project's learnings about not using nil to branch behavior, add a new single-arity function in `lib/ancestry/people.ex` right before the two-arity version (before line 93):

```elixir
def search_all_people(query) do
  escaped =
    query
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")

  like = "%#{escaped}%"

  Repo.all(
    from p in Person,
      where:
        ilike(p.given_name, ^like) or
          ilike(p.surname, ^like) or
          ilike(p.nickname, ^like) or
          fragment(
            "EXISTS (SELECT 1 FROM unnest(?) AS name WHERE name ILIKE ?)",
            p.alternate_names,
            ^like
          ),
      order_by: [asc: p.surname, asc: p.given_name],
      limit: 20,
      preload: [:families]
  )
end
```

**Step 5: Run tests to verify they pass**

Run: `mix test test/ancestry/galleries_test.exs`
Expected: All PASS.

**Step 6: Commit**

```
feat: add context functions for tagging people in photos
```

---

### Task 3: Generalize right panel — rename comments_open to panel_open

**Files:**
- Modify: `lib/web/live/gallery_live/show.ex` (rename assigns, add photo_people assign)
- Modify: `lib/web/live/gallery_live/show.html.heex` (rename references, restructure panel)

**Step 1: Update assigns in show.ex mount (line 25)**

Change:
```elixir
|> assign(:comments_open, false)
|> assign(:comments_topic, nil)
```
To:
```elixir
|> assign(:panel_open, false)
|> assign(:comments_topic, nil)
|> assign(:photo_people, [])
```

**Step 2: Rename all `comments_open` references in show.ex**

Replace all `@comments_open` / `:comments_open` with `@panel_open` / `:panel_open` in the following locations:
- `handle_event("toggle_comments", ...)` (line 136): `not socket.assigns.panel_open` and `assign(:panel_open, true)`
- `cleanup_comments_subscription/1` (line 301): `assign(:panel_open, false)`
- `resubscribe_comments/2` (line 306): `socket.assigns.panel_open`

Also rename the event from `toggle_comments` to `toggle_panel`.

**Step 3: Load photo_people when opening lightbox**

In `handle_event("photo_clicked", ...)` (line 131), change:
```elixir
{:noreply, assign(socket, :selected_photo, Galleries.get_photo!(id))}
```
To:
```elixir
photo = Galleries.get_photo!(id)
{:noreply,
 socket
 |> assign(:selected_photo, photo)
 |> assign(:photo_people, Galleries.list_photo_people(photo.id))}
```

**Step 4: Reload photo_people on lightbox navigation**

In `navigate_lightbox/2` (around line 290-292), add `assign(:photo_people, ...)`:
```elixir
socket
|> assign(:selected_photo, new_photo)
|> assign(:photo_people, Galleries.list_photo_people(new_photo.id))
|> resubscribe_comments(new_photo)
```

In `handle_event("lightbox_select", ...)` (line 180-184), add:
```elixir
def handle_event("lightbox_select", %{"id" => id}, socket) do
  new_photo = Galleries.get_photo!(String.to_integer(id))

  {:noreply,
   socket
   |> assign(:selected_photo, new_photo)
   |> assign(:photo_people, Galleries.list_photo_people(new_photo.id))
   |> resubscribe_comments(new_photo)}
end
```

**Step 5: Update template — rename toggle_comments to toggle_panel**

In `show.html.heex`, the toggle button (line 369) and all `@comments_open` references:
- Change `phx-click="toggle_comments"` to `phx-click="toggle_panel"`
- Change all `@comments_open` to `@panel_open`
- Change the button icon from `hero-chat-bubble-left-right` to `hero-information-circle`
- Change title from "Toggle comments" to "Toggle panel"
- Add `id="toggle-panel-btn"` to the button

**Step 6: Restructure right panel in template**

Replace the current comments panel section (lines 417-425):
```heex
<%= if @comments_open do %>
  <div class="hidden lg:flex w-80 shrink-0 border-l border-white/10">
    <.live_component
      module={Web.Comments.PhotoCommentsComponent}
      id="photo-comments"
      photo_id={@selected_photo.id}
    />
  </div>
<% end %>
```

With the generalized panel:
```heex
<%= if @panel_open do %>
  <div class="hidden lg:flex flex-col w-80 shrink-0 border-l border-white/10 bg-black/80 text-white">
    <%!-- People section --%>
    <div class="shrink-0 border-b border-white/10">
      <div class="flex items-center justify-between px-4 py-3">
        <div class="flex items-center gap-2">
          <h3 class="text-sm font-semibold text-white/90 tracking-wide">People</h3>
          <%= if @photo_people != [] do %>
            <span class="text-xs bg-white/10 text-white/60 px-1.5 py-0.5 rounded-full">
              {length(@photo_people)}
            </span>
          <% end %>
        </div>
        <button
          phx-click="toggle_panel"
          class="p-1.5 rounded-lg text-white/40 hover:text-white hover:bg-white/10 transition-colors"
        >
          <.icon name="hero-x-mark" class="w-4 h-4" />
        </button>
      </div>
      <div id="photo-person-list" class="px-4 pb-3 max-h-48 overflow-y-auto">
        <%= if @photo_people == [] do %>
          <p class="text-sm text-white/30 py-2">Click on the photo to tag people</p>
        <% else %>
          <div class="space-y-1">
            <%= for pp <- @photo_people do %>
              <div
                id={"photo-person-#{pp.id}"}
                class="flex items-center gap-2 px-2 py-1.5 rounded-lg hover:bg-white/10 transition-colors group"
                data-person-id={pp.person_id}
                phx-hook=".PersonHighlight"
              >
                <%= if pp.person.photo && pp.person.photo_status == "processed" do %>
                  <img
                    src={Ancestry.Uploaders.PersonPhoto.url({pp.person.photo, pp.person}, :thumbnail)}
                    class="w-6 h-6 rounded-full object-cover shrink-0"
                  />
                <% else %>
                  <div class="w-6 h-6 rounded-full bg-white/10 flex items-center justify-center shrink-0">
                    <.icon name="hero-user" class="w-3.5 h-3.5 text-white/40" />
                  </div>
                <% end %>
                <span class="text-sm text-white/80 truncate flex-1">
                  {Ancestry.People.Person.display_name(pp.person)}
                </span>
                <button
                  phx-click="untag_person"
                  phx-value-photo-id={pp.photo_id}
                  phx-value-person-id={pp.person_id}
                  class="p-1 rounded text-white/20 hover:text-red-400 opacity-0 group-hover:opacity-100 transition-all shrink-0"
                  title="Remove tag"
                >
                  <.icon name="hero-x-mark" class="w-3.5 h-3.5" />
                </button>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>

    <%!-- Comments section --%>
    <div class="flex-1 min-h-0">
      <.live_component
        module={Web.Comments.PhotoCommentsComponent}
        id="photo-comments"
        photo_id={@selected_photo.id}
      />
    </div>
  </div>
<% end %>
```

**Step 7: Remove the close button from PhotoCommentsComponent**

Since the panel close is now handled by the parent's X button on the People section header, update `lib/web/live/comments/photo_comments_component.ex`:
- Remove the close button from the header (lines 100-107)
- Remove the `handle_event("close_comments", ...)` (lines 88-91)
- The header should just show "Comments" without a close button

**Step 8: Run tests**

Run: `mix test`
Expected: All existing tests pass with renamed assigns.

**Step 9: Commit**

```
refactor: generalize right panel to stacked People + Comments sections
```

---

### Task 4: Server-side event handlers — tag, untag, search

**Files:**
- Modify: `lib/web/live/gallery_live/show.ex` (add handle_event clauses)

**Step 1: Add tag_person event handler**

Add to `show.ex` after the `lightbox_select` handler:

```elixir
def handle_event("tag_person", %{"person_id" => person_id, "x" => x, "y" => y}, socket) do
  photo = socket.assigns.selected_photo

  case Galleries.tag_person_in_photo(photo.id, String.to_integer(person_id), x, y) do
    {:ok, _} ->
      {:noreply, assign(socket, :photo_people, Galleries.list_photo_people(photo.id))}

    {:error, _} ->
      {:noreply, socket}
  end
end
```

**Step 2: Add untag_person event handler**

```elixir
def handle_event("untag_person", %{"photo-id" => photo_id, "person-id" => person_id}, socket) do
  :ok = Galleries.untag_person_from_photo(String.to_integer(photo_id), String.to_integer(person_id))

  {:noreply,
   assign(socket, :photo_people, Galleries.list_photo_people(socket.assigns.selected_photo.id))}
end
```

**Step 3: Add search_people_for_tag event handler**

This handler uses `{:reply, ...}` to return results directly to the JS hook's `pushEvent` callback:

```elixir
def handle_event("search_people_for_tag", %{"query" => query}, socket) do
  results =
    if String.length(query) >= 2 do
      Ancestry.People.search_all_people(query)
    else
      []
    end

  {:reply, %{results: Enum.map(results, fn p ->
    %{
      id: p.id,
      name: Ancestry.People.Person.display_name(p),
      has_photo: p.photo != nil && p.photo_status == "processed",
      photo_url: if(p.photo && p.photo_status == "processed",
        do: Ancestry.Uploaders.PersonPhoto.url({p.photo, p}, :thumbnail),
        else: nil
      )
    }
  end)}, socket}
end
```

**Step 4: Run tests**

Run: `mix test`
Expected: All pass.

**Step 5: Commit**

```
feat: add server-side event handlers for photo person tagging
```

---

### Task 5: Photo tagger JS hook and popover UI

**Files:**
- Modify: `lib/web/live/gallery_live/show.html.heex` (add hook, circles, popover)

**Step 1: Wrap the lightbox image in a relative container**

Replace the bare `<img>` in the lightbox image area (around line 403-407):
```heex
<img
  src={Ancestry.Uploaders.Photo.url({@selected_photo.image, @selected_photo}, :large)}
  alt={@selected_photo.original_filename}
  class="max-h-full max-w-full object-contain rounded-lg shadow-2xl"
/>
```

With a container that holds the image, the circles overlay, and the popover:
```heex
<div
  id="photo-tagger"
  class="relative max-h-full max-w-full"
  phx-hook=".PhotoTagger"
  phx-update="ignore"
>
  <img
    id="lightbox-image"
    src={Ancestry.Uploaders.Photo.url({@selected_photo.image, @selected_photo}, :large)}
    alt={@selected_photo.original_filename}
    class="max-h-full max-w-full object-contain rounded-lg shadow-2xl"
  />
  <div id="tag-circles" class="absolute inset-0 pointer-events-none"></div>
  <div id="tag-popover" class="hidden absolute z-20"></div>
</div>
```

**Step 2: Add the colocated `.PhotoTagger` hook**

Add this script tag in the template (after the lightbox closing `<% end %>`, near the bottom). This hook uses safe DOM construction methods instead of string interpolation to prevent XSS:

```heex
<script :type={Phoenix.LiveView.ColocatedHook} name=".PhotoTagger">
  export default {
    mounted() {
      this.image = this.el.querySelector("#lightbox-image")
      this.circlesContainer = this.el.querySelector("#tag-circles")
      this.popover = this.el.querySelector("#tag-popover")
      this.pendingClick = null

      this.image.addEventListener("click", (e) => {
        const rect = this.image.getBoundingClientRect()
        const x = (e.clientX - rect.left) / rect.width
        const y = (e.clientY - rect.top) / rect.height

        this.pendingClick = { x, y }
        this.showPopover(e.clientX - rect.left, e.clientY - rect.top, rect)
      })

      this.handleEvent("photo_people_updated", ({ people }) => {
        this.renderCircles(people)
        this.hidePopover()
      })

      this.handleEvent("highlight_person", ({ person_id }) => {
        this.highlightCircle(person_id)
      })

      this.handleEvent("unhighlight_person", ({ person_id }) => {
        this.unhighlightCircle(person_id)
      })
    },

    showPopover(left, top, imageRect) {
      const popoverWidth = 256
      const popoverLeft = Math.min(left, imageRect.width - popoverWidth - 8)

      // Build popover DOM safely
      this.popover.replaceChildren()
      const wrapper = document.createElement("div")
      wrapper.className = "bg-neutral-900 border border-white/20 rounded-xl shadow-2xl w-64 overflow-hidden"

      const inputWrap = document.createElement("div")
      inputWrap.className = "px-3 py-2 border-b border-white/10"
      const input = document.createElement("input")
      input.id = "tag-search-input"
      input.type = "text"
      input.placeholder = "Search people..."
      input.className = "w-full bg-transparent border-none text-sm text-white placeholder-white/40 focus:outline-none"
      inputWrap.appendChild(input)
      wrapper.appendChild(inputWrap)

      const resultsDiv = document.createElement("div")
      resultsDiv.id = "tag-search-results"
      resultsDiv.className = "max-h-48 overflow-y-auto p-1"
      const hint = document.createElement("p")
      hint.className = "text-xs text-white/30 px-2 py-3 text-center"
      hint.textContent = "Type to search"
      resultsDiv.appendChild(hint)
      wrapper.appendChild(resultsDiv)

      this.popover.appendChild(wrapper)
      this.popover.style.left = `${Math.max(0, popoverLeft)}px`
      this.popover.style.top = `${Math.min(top + 24, imageRect.height - 200)}px`
      this.popover.classList.remove("hidden")

      setTimeout(() => input.focus(), 50)

      let debounceTimer = null
      input.addEventListener("input", (e) => {
        clearTimeout(debounceTimer)
        debounceTimer = setTimeout(() => {
          this.pushEvent("search_people_for_tag", { query: e.target.value }, (reply) => {
            this.renderSearchResults(reply.results)
          })
        }, 300)
      })

      input.addEventListener("keydown", (e) => {
        if (e.key === "Escape") {
          e.stopPropagation()
          this.hidePopover()
        }
      })

      setTimeout(() => {
        this._clickAway = (e) => {
          if (!this.popover.contains(e.target) && e.target !== this.image) {
            this.hidePopover()
          }
        }
        document.addEventListener("click", this._clickAway)
      }, 100)
    },

    hidePopover() {
      this.popover.classList.add("hidden")
      this.popover.replaceChildren()
      this.pendingClick = null
      if (this._clickAway) {
        document.removeEventListener("click", this._clickAway)
        this._clickAway = null
      }
    },

    renderSearchResults(results) {
      const container = this.popover.querySelector("#tag-search-results")
      if (!container) return
      container.replaceChildren()

      if (results.length === 0) {
        const p = document.createElement("p")
        p.className = "text-xs text-white/30 px-2 py-3 text-center"
        p.textContent = "No results"
        container.appendChild(p)
        return
      }

      results.forEach(person => {
        const btn = document.createElement("button")
        btn.dataset.personId = person.id
        btn.className = "flex items-center gap-2 w-full px-2 py-1.5 rounded-lg hover:bg-white/10 transition-colors text-left"

        if (person.has_photo) {
          const img = document.createElement("img")
          img.src = person.photo_url
          img.className = "w-6 h-6 rounded-full object-cover shrink-0"
          btn.appendChild(img)
        } else {
          const placeholder = document.createElement("div")
          placeholder.className = "w-6 h-6 rounded-full bg-white/10 flex items-center justify-center shrink-0"
          const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg")
          svg.setAttribute("class", "w-3.5 h-3.5 text-white/40")
          svg.setAttribute("fill", "none")
          svg.setAttribute("viewBox", "0 0 24 24")
          svg.setAttribute("stroke", "currentColor")
          const path = document.createElementNS("http://www.w3.org/2000/svg", "path")
          path.setAttribute("stroke-linecap", "round")
          path.setAttribute("stroke-linejoin", "round")
          path.setAttribute("stroke-width", "2")
          path.setAttribute("d", "M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z")
          svg.appendChild(path)
          placeholder.appendChild(svg)
          btn.appendChild(placeholder)
        }

        const nameSpan = document.createElement("span")
        nameSpan.className = "text-sm text-white/80 truncate"
        nameSpan.textContent = person.name
        btn.appendChild(nameSpan)

        btn.addEventListener("click", (e) => {
          e.stopPropagation()
          if (this.pendingClick) {
            this.pushEvent("tag_person", {
              person_id: person.id,
              x: this.pendingClick.x,
              y: this.pendingClick.y
            })
          }
        })

        container.appendChild(btn)
      })
    },

    renderCircles(people) {
      this.circlesContainer.replaceChildren()

      people.forEach(pp => {
        const circle = document.createElement("div")
        circle.dataset.circlePersonId = pp.person_id
        circle.className = "absolute w-10 h-10 -ml-5 -mt-5 rounded-full border-2 border-dashed border-white/40 transition-all duration-200 pointer-events-auto"
        circle.style.left = `${pp.x * 100}%`
        circle.style.top = `${pp.y * 100}%`

        const tooltip = document.createElement("div")
        tooltip.className = "absolute top-full left-1/2 -translate-x-1/2 mt-1 px-2 py-0.5 bg-black/80 rounded text-xs text-white/80 whitespace-nowrap opacity-0 pointer-events-none tag-tooltip transition-opacity"
        tooltip.textContent = pp.person_name
        circle.appendChild(tooltip)

        circle.addEventListener("mouseenter", () => { tooltip.style.opacity = "1" })
        circle.addEventListener("mouseleave", () => { tooltip.style.opacity = "0" })

        this.circlesContainer.appendChild(circle)
      })
    },

    highlightCircle(personId) {
      const circle = this.circlesContainer.querySelector(`[data-circle-person-id="${personId}"]`)
      if (circle) {
        circle.classList.remove("border-white/40")
        circle.classList.add("border-white", "scale-110", "shadow-lg", "shadow-white/20")
        const tooltip = circle.querySelector(".tag-tooltip")
        if (tooltip) tooltip.style.opacity = "1"
      }
    },

    unhighlightCircle(personId) {
      const circle = this.circlesContainer.querySelector(`[data-circle-person-id="${personId}"]`)
      if (circle) {
        circle.classList.add("border-white/40")
        circle.classList.remove("border-white", "scale-110", "shadow-lg", "shadow-white/20")
        const tooltip = circle.querySelector(".tag-tooltip")
        if (tooltip) tooltip.style.opacity = "0"
      }
    },

    destroyed() {
      if (this._clickAway) {
        document.removeEventListener("click", this._clickAway)
      }
    }
  }
</script>
```

**Step 3: Push photo_people data to the hook**

In `show.ex`, after any assign of `:photo_people`, also push the event to the JS hook. Create a helper function:

```elixir
defp push_photo_people(socket) do
  people_data =
    Enum.map(socket.assigns.photo_people, fn pp ->
      %{
        person_id: pp.person_id,
        x: pp.x,
        y: pp.y,
        person_name: Ancestry.People.Person.display_name(pp.person)
      }
    end)

  push_event(socket, "photo_people_updated", %{people: people_data})
end
```

Then update all places that assign `:photo_people` to also call `push_photo_people/1`:
- `photo_clicked` handler
- `navigate_lightbox/2`
- `lightbox_select` handler
- `tag_person` handler
- `untag_person` handler

For example, the `tag_person` handler becomes:
```elixir
def handle_event("tag_person", %{"person_id" => person_id, "x" => x, "y" => y}, socket) do
  photo = socket.assigns.selected_photo

  case Galleries.tag_person_in_photo(photo.id, String.to_integer(person_id), x, y) do
    {:ok, _} ->
      socket =
        socket
        |> assign(:photo_people, Galleries.list_photo_people(photo.id))
        |> push_photo_people()

      {:noreply, socket}

    {:error, _} ->
      {:noreply, socket}
  end
end
```

And the `photo_clicked` handler becomes:
```elixir
photo = Galleries.get_photo!(id)
socket =
  socket
  |> assign(:selected_photo, photo)
  |> assign(:photo_people, Galleries.list_photo_people(photo.id))
  |> push_photo_people()

{:noreply, socket}
```

**Step 4: Run the dev server and test manually**

Run: `iex -S mix phx.server`
Test: Open a gallery, click a processed photo, click on the image, search for a person, select them. Verify the circle appears and the person is listed in the panel.

**Step 5: Commit**

```
feat: add photo tagger JS hook with popover search and circle overlay
```

---

### Task 6: Sidebar hover highlights circle on photo

**Files:**
- Modify: `lib/web/live/gallery_live/show.html.heex` (add `.PersonHighlight` hook)
- Modify: `lib/web/live/gallery_live/show.ex` (add highlight event handlers)

**Step 1: Add the `.PersonHighlight` colocated hook**

Add this script tag alongside the `.PhotoTagger` hook:

```heex
<script :type={Phoenix.LiveView.ColocatedHook} name=".PersonHighlight">
  export default {
    mounted() {
      this.el.addEventListener("mouseenter", () => {
        this.pushEvent("highlight_person_on_photo", { id: this.el.id })
      })

      this.el.addEventListener("mouseleave", () => {
        this.pushEvent("unhighlight_person_on_photo", { id: this.el.id })
      })
    }
  }
</script>
```

**Step 2: Handle highlight events in show.ex**

Add these event handlers (they push events to the PhotoTagger hook):

```elixir
def handle_event("highlight_person_on_photo", %{"id" => dom_id}, socket) do
  pp_id = dom_id |> String.replace("photo-person-", "") |> String.to_integer()
  pp = Enum.find(socket.assigns.photo_people, &(&1.id == pp_id))

  if pp do
    {:noreply, push_event(socket, "highlight_person", %{person_id: pp.person_id})}
  else
    {:noreply, socket}
  end
end

def handle_event("unhighlight_person_on_photo", %{"id" => dom_id}, socket) do
  pp_id = dom_id |> String.replace("photo-person-", "") |> String.to_integer()
  pp = Enum.find(socket.assigns.photo_people, &(&1.id == pp_id))

  if pp do
    {:noreply, push_event(socket, "unhighlight_person", %{person_id: pp.person_id})}
  else
    {:noreply, socket}
  end
end
```

**Step 3: Test manually**

Run: `iex -S mix phx.server`
Test: Tag a person, then hover over their name in the sidebar. The circle on the photo should brighten and scale up.

**Step 4: Commit**

```
feat: add sidebar-to-photo hover highlight for tagged people
```

---

### Task 7: E2E test

**Files:**
- Create: `test/user_flows/link_people_in_photos_test.exs`

**Step 1: Write the E2E test**

```elixir
defmodule Web.UserFlows.LinkPeopleInPhotosTest do
  use Web.E2ECase

  # Given a family with a gallery containing a processed photo
  # And two existing people in the system
  #
  # When the user opens the gallery and clicks on the photo
  # Then the lightbox opens
  #
  # When the user opens the panel and clicks on the photo image
  # Then a popover appears with a search input
  #
  # When the user searches for a person name
  # Then matching results appear
  #
  # When the user selects a person from the results
  # Then a circle appears on the photo at the clicked position
  # And the person appears in the right panel people list
  #
  # When the user clicks X next to the person in the right panel
  # Then the person is removed from the list
  # And the circle disappears from the photo
  setup do
    family = insert(:family, name: "Photo Tag Family")
    gallery = insert(:gallery, name: "Summer 2025", family: family)

    photo =
      insert(:photo, gallery: gallery, original_filename: "beach.jpg")
      |> ensure_photo_file()

    person1 = insert(:person, given_name: "Alice", surname: "Wonderland")
    person2 = insert(:person, given_name: "Bob", surname: "Builder")

    %{family: family, gallery: gallery, photo: photo, person1: person1, person2: person2}
  end

  test "tag and untag people on a photo", %{
    conn: conn,
    family: family,
    gallery: gallery,
    person1: person1
  } do
    # Navigate to the gallery
    conn =
      conn
      |> visit(~p"/families/#{family.id}/galleries/#{gallery.id}")
      |> wait_liveview()

    # Click the photo to open lightbox
    conn =
      conn
      |> click("#photo-grid div[phx-click]")
      |> assert_has("#lightbox")

    # Open the panel
    conn = click(conn, "#toggle-panel-btn")

    # Click on the photo image to start tagging
    conn = PhoenixTest.Playwright.evaluate(conn, """
      (function() {
        const img = document.querySelector("#lightbox-image");
        const rect = img.getBoundingClientRect();
        const x = rect.left + rect.width * 0.3;
        const y = rect.top + rect.height * 0.4;
        img.dispatchEvent(new MouseEvent("click", {
          clientX: x, clientY: y, bubbles: true
        }));
      })();
    """)

    # Search for Alice in the popover
    conn = assert_has(conn, "#tag-search-input", timeout: 2_000)
    conn = PhoenixTest.Playwright.type(conn, "#tag-search-input", "Alice")

    # Wait for search results and click Alice
    conn = assert_has(conn, "[data-person-id='#{person1.id}']", timeout: 5_000)
    conn = click(conn, "[data-person-id='#{person1.id}']")

    # Verify Alice appears in the panel people list
    conn = assert_has(conn, "#photo-person-list", text: "Wonderland", timeout: 3_000)

    # Verify circle appears on the photo
    conn = assert_has(conn, "[data-circle-person-id='#{person1.id}']", timeout: 2_000)

    # Remove the tag via X button in the panel — find the untag button inside the person row
    conn =
      PhoenixTest.Playwright.evaluate(conn, """
        (function() {
          const row = document.querySelector("[id^='photo-person-']");
          const btn = row.querySelector("button[phx-click='untag_person']");
          btn.click();
        })();
      """)

    # Verify person is removed
    conn
    |> refute_has("[data-circle-person-id='#{person1.id}']", timeout: 3_000)
  end
end
```

**Note:** This test may need adjustments based on exact DOM IDs and selectors after implementation. The key patterns are correct — factory setup, E2E navigation, Playwright JS evaluation for image clicks, and assertion on DOM elements.

**Step 2: Run the E2E test**

Run: `mix test test/user_flows/link_people_in_photos_test.exs`
Expected: All pass (may require iterative debugging of selectors).

**Step 3: Commit**

```
test: add E2E test for tagging people in photos
```

---

### Task 8: Final cleanup and precommit

**Step 1: Run precommit**

Run: `mix precommit`
Expected: Compiles clean (no warnings), formatted, all tests pass.

**Step 2: Fix any issues found by precommit**

Address warnings, formatting issues, or test failures.

**Step 3: Final commit if needed**

```
chore: fix warnings and formatting from precommit
```
