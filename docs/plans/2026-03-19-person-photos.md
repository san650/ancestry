# Person Photos Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Show all photos where a person is tagged in a masonry gallery on their show page, with full lightbox, comments, and tagging — reusing shared components extracted from the gallery page.

**Architecture:** Extract lightbox, photo grid, and event handling from `GalleryLive.Show` into shared modules (`Web.Components.PhotoGallery` for templates, `Web.PhotoInteractions` for event logic). Both `GalleryLive.Show` and `PersonLive.Show` delegate to these shared modules. A new query `list_photos_for_person/1` provides the data.

**Tech Stack:** Phoenix LiveView, Ecto, existing PhotoTagger/PersonHighlight JS hooks, existing PhotoCommentsComponent LiveComponent.

---

### Task 1: Add `list_photos_for_person/1` query

**Files:**
- Modify: `lib/ancestry/galleries.ex`
- Test: `test/ancestry/galleries_test.exs`

**Step 1: Write the failing test**

Create or open `test/ancestry/galleries_test.exs` and add:

```elixir
defmodule Ancestry.GalleriesTest do
  use Ancestry.DataCase

  alias Ancestry.Galleries
  alias Ancestry.People
  alias Ancestry.Families

  describe "list_photos_for_person/1" do
    test "returns processed photos where person is tagged, ordered by inserted_at desc" do
      # Setup: family -> gallery -> photos
      {:ok, family} = Families.create_family(%{name: "Test Family"})
      {:ok, gallery} = Galleries.create_gallery(%{name: "Test Gallery", family_id: family.id})

      {:ok, person} = People.create_person(family, %{given_name: "Alice", surname: "Smith"})

      # Create two processed photos
      {:ok, photo1} = Galleries.create_photo(%{
        gallery_id: gallery.id,
        original_path: "/tmp/test1.jpg",
        original_filename: "test1.jpg",
        content_type: "image/jpeg"
      })
      {:ok, photo1} = Galleries.update_photo_processed(photo1, "test1.jpg")

      {:ok, photo2} = Galleries.create_photo(%{
        gallery_id: gallery.id,
        original_path: "/tmp/test2.jpg",
        original_filename: "test2.jpg",
        content_type: "image/jpeg"
      })
      {:ok, photo2} = Galleries.update_photo_processed(photo2, "test2.jpg")

      # Create a pending photo (should not appear)
      {:ok, photo3} = Galleries.create_photo(%{
        gallery_id: gallery.id,
        original_path: "/tmp/test3.jpg",
        original_filename: "test3.jpg",
        content_type: "image/jpeg"
      })

      # Tag person in photo1 and photo2 (not photo3)
      {:ok, _} = Galleries.tag_person_in_photo(photo1.id, person.id, 0.5, 0.5)
      {:ok, _} = Galleries.tag_person_in_photo(photo2.id, person.id, 0.3, 0.3)

      # Also tag person in the pending photo3 — should still not appear
      {:ok, _} = Galleries.tag_person_in_photo(photo3.id, person.id, 0.1, 0.1)

      result = Galleries.list_photos_for_person(person.id)

      # Should only include processed photos, ordered by inserted_at desc
      assert length(result) == 2
      assert List.first(result).id == photo2.id
      assert List.last(result).id == photo1.id

      # Each photo should have gallery preloaded
      assert List.first(result).gallery != nil
    end

    test "returns empty list when person has no tagged photos" do
      {:ok, family} = Families.create_family(%{name: "Test Family"})
      {:ok, person} = People.create_person(family, %{given_name: "Bob", surname: "Jones"})

      assert Galleries.list_photos_for_person(person.id) == []
    end
  end
end
```

**Step 2: Run the test to verify it fails**

Run: `mix test test/ancestry/galleries_test.exs --max-failures 1`
Expected: FAIL — `list_photos_for_person/1` is undefined.

**Step 3: Implement the query**

In `lib/ancestry/galleries.ex`, add:

```elixir
def list_photos_for_person(person_id) do
  Repo.all(
    from p in Photo,
      join: pp in PhotoPerson,
      on: pp.photo_id == p.id,
      where: pp.person_id == ^person_id and p.status == "processed",
      order_by: [desc: p.inserted_at, desc: p.id],
      preload: [:gallery]
  )
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/ancestry/galleries_test.exs`
Expected: PASS

**Step 5: Commit**

```bash
git add lib/ancestry/galleries.ex test/ancestry/galleries_test.exs
git commit -m "feat: add list_photos_for_person query"
```

---

### Task 2: Extract `Web.Components.PhotoGallery` from GalleryLive.Show template

**Files:**
- Create: `lib/web/components/photo_gallery.ex`
- Modify: `lib/web/live/gallery_live/show.html.heex`

This task extracts the photo grid and lightbox template blocks into a shared function component module. The gallery template then calls these components.

**Step 1: Create `Web.Components.PhotoGallery`**

Create `lib/web/components/photo_gallery.ex` with two function components extracted from `show.html.heex`:

```elixir
defmodule Web.Components.PhotoGallery do
  use Phoenix.Component

  import Web.CoreComponents
  alias Web.Comments.PhotoCommentsComponent

  @doc """
  Renders a masonry or uniform photo grid from a stream.

  ## Assigns
  - `id` (required) — DOM id for the grid container
  - `photos` — the stream (e.g. `@streams.photos`)
  - `grid_layout` — `:masonry` or `:uniform` (default `:masonry`)
  - `selection_mode` — boolean, default `false`
  - `selected_ids` — MapSet of selected photo IDs, default `MapSet.new()`
  """
  attr :id, :string, required: true
  attr :photos, :any, required: true
  attr :grid_layout, :atom, default: :masonry
  attr :selection_mode, :boolean, default: false
  attr :selected_ids, :any, default: nil

  def photo_grid(assigns) do
    assigns = assign_new(assigns, :selected_ids, fn -> MapSet.new() end)

    ~H"""
    <div
      id={@id}
      phx-update="stream"
      class={[
        if(@grid_layout == :masonry,
          do: "masonry-grid columns-2 sm:columns-3 md:columns-4 lg:columns-5 gap-2",
          else: "uniform-grid grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-2"
        )
      ]}
    >
      <div
        id={"#{@id}-empty"}
        class="hidden only:block col-span-full text-center py-20 text-base-content/30"
      >
        No photos yet
      </div>
      <div
        :for={{id, photo} <- @photos}
        id={id}
        class={[
          "relative group rounded-xl overflow-hidden bg-base-200 cursor-pointer",
          @grid_layout == :masonry && "mb-2 break-inside-avoid",
          if(@selection_mode && MapSet.member?(@selected_ids, photo.id),
            do: "outline outline-3 outline-primary outline-offset-2",
            else: "outline outline-3 outline-transparent outline-offset-2"
          )
        ]}
        phx-click={JS.push("photo_clicked", value: %{id: photo.id})}
      >
        <%= cond do %>
          <% photo.status == "pending" -> %>
            <div class="aspect-square flex flex-col items-center justify-center gap-2">
              <.icon
                name="hero-photo"
                class="w-8 h-8 text-base-content/20 animate__animated animate__pulse animate__infinite"
              />
              <p class="text-xs text-base-content/30 font-medium">Processing</p>
            </div>
          <% photo.status == "failed" -> %>
            <div class="aspect-square flex flex-col items-center justify-center gap-2 bg-error/5">
              <.icon name="hero-exclamation-triangle" class="w-8 h-8 text-error/50" />
              <p class="text-xs text-error/70">Processing failed</p>
            </div>
          <% true -> %>
            <img
              src={Ancestry.Uploaders.Photo.url({photo.image, photo}, :thumbnail)}
              alt={photo.original_filename}
              class="w-full h-full object-cover"
              loading="lazy"
            />
        <% end %>

        <%= if @selection_mode do %>
          <div class={[
            "absolute inset-0 transition-colors",
            MapSet.member?(@selected_ids, photo.id) && "bg-primary/30"
          ]}>
            <div class={[
              "absolute top-2 right-2 w-6 h-6 rounded-full border-2 transition-all flex items-center justify-center",
              if(MapSet.member?(@selected_ids, photo.id),
                do: "bg-primary border-primary",
                else: "border-white/70 bg-black/20"
              )
            ]}>
              <%= if MapSet.member?(@selected_ids, photo.id) do %>
                <.icon name="hero-check" class="w-3.5 h-3.5 text-white" />
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  @doc """
  Renders a full-screen photo lightbox with navigation, people panel, and comments.

  ## Assigns
  - `selected_photo` (required) — the currently displayed photo
  - `photos` (required) — list of all photos for thumbnail strip and navigation
  - `panel_open` — boolean, default `false`
  - `photo_people` — list of PhotoPerson records, default `[]`
  """
  attr :selected_photo, :any, required: true
  attr :photos, :list, required: true
  attr :panel_open, :boolean, default: false
  attr :photo_people, :list, default: []

  def lightbox(assigns) do
    ~H"""
    <div
      id="lightbox"
      class="fixed inset-0 z-50 bg-black/95 flex flex-col select-none"
      phx-window-keydown="lightbox_keydown"
    >
      <%!-- Lightbox top bar --%>
      <div class="flex items-center justify-between px-6 py-4 shrink-0">
        <p class="text-white/50 text-sm truncate max-w-xs">{@selected_photo.original_filename}</p>
        <div class="flex items-center gap-3">
          <a
            href={
              Ancestry.Uploaders.Photo.url({@selected_photo.image, @selected_photo}, :original)
            }
            download={@selected_photo.original_filename}
            class="flex items-center gap-1.5 px-3 py-1.5 bg-white/10 hover:bg-white/20 text-white rounded-lg text-sm font-medium transition-colors"
          >
            <.icon name="hero-arrow-down-tray" class="w-4 h-4" /> Download original
          </a>
          <button
            id="toggle-panel-btn"
            phx-click="toggle_panel"
            class={[
              "p-2 rounded-lg transition-colors",
              if(@panel_open,
                do: "text-primary bg-white/10",
                else: "text-white/50 hover:text-white hover:bg-white/10"
              )
            ]}
            title="Toggle panel"
          >
            <.icon name="hero-information-circle" class="w-5 h-5" />
          </button>
          <button
            phx-click="close_lightbox"
            class="p-2 text-white/50 hover:text-white rounded-lg hover:bg-white/10 transition-colors"
          >
            <.icon name="hero-x-mark" class="w-5 h-5" />
          </button>
        </div>
      </div>

      <%!-- Main image area + comments panel --%>
      <div class="flex-1 flex min-h-0">
        <div class={[
          "flex-1 flex items-center justify-center relative min-h-0 px-16",
          @panel_open && "lg:flex-[2]"
        ]}>
          <button
            phx-click={JS.push("lightbox_keydown", value: %{key: "ArrowLeft"})}
            class="absolute left-3 p-3 text-white/40 hover:text-white hover:bg-white/10 rounded-full transition-colors z-10"
          >
            <.icon name="hero-chevron-left" class="w-7 h-7" />
          </button>

          <img
            id="lightbox-image"
            src={Ancestry.Uploaders.Photo.url({@selected_photo.image, @selected_photo}, :large)}
            alt={@selected_photo.original_filename}
            class="max-h-full max-w-full object-contain rounded-lg shadow-2xl"
            phx-hook="PhotoTagger"
          />

          <button
            phx-click={JS.push("lightbox_keydown", value: %{key: "ArrowRight"})}
            class="absolute right-3 p-3 text-white/40 hover:text-white hover:bg-white/10 rounded-full transition-colors z-10"
          >
            <.icon name="hero-chevron-right" class="w-7 h-7" />
          </button>
        </div>

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
                        phx-hook="PersonHighlight"
                      >
                        <%= if pp.person.photo && pp.person.photo_status == "processed" do %>
                          <img
                            src={
                              Ancestry.Uploaders.PersonPhoto.url(
                                {pp.person.photo, pp.person},
                                :thumbnail
                              )
                            }
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
                module={PhotoCommentsComponent}
                id="photo-comments"
                photo_id={@selected_photo.id}
              />
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Thumbnail strip --%>
      <div class="shrink-0 flex gap-2 px-6 py-4 overflow-x-auto">
        <%= for photo <- @photos do %>
          <button
            phx-click="lightbox_select"
            phx-value-id={photo.id}
            class={[
              "shrink-0 w-16 h-16 rounded-lg overflow-hidden border-2 transition-all duration-150",
              if(photo.id == @selected_photo.id,
                do: "border-white scale-105 shadow-lg",
                else: "border-transparent opacity-50 hover:opacity-90"
              )
            ]}
          >
            <%= if photo.status == "processed" do %>
              <img
                src={Ancestry.Uploaders.Photo.url({photo.image, photo}, :thumbnail)}
                alt={photo.original_filename}
                class="w-full h-full object-cover"
              />
            <% else %>
              <div class="w-full h-full bg-white/10 flex items-center justify-center">
                <.icon name="hero-photo" class="w-5 h-5 text-white/30" />
              </div>
            <% end %>
          </button>
        <% end %>
      </div>
    </div>
    """
  end
end
```

**Step 2: Update `GalleryLive.Show` template to use shared components**

Replace the photo grid block (lines 94-166) and lightbox block (lines 347-526) in `lib/web/live/gallery_live/show.html.heex` with calls to the shared components:

For the photo grid, replace lines 94-166 with:
```heex
<Web.Components.PhotoGallery.photo_grid
  id="photo-grid"
  photos={@streams.photos}
  grid_layout={@grid_layout}
  selection_mode={@selection_mode}
  selected_ids={@selected_ids}
/>
```

For the lightbox, replace lines 347-526 with:
```heex
<%= if @selected_photo do %>
  <Web.Components.PhotoGallery.lightbox
    selected_photo={@selected_photo}
    photos={Ancestry.Galleries.list_photos(@gallery.id)}
    panel_open={@panel_open}
    photo_people={@photo_people}
  />
<% end %>
```

**Step 3: Verify the gallery page still works**

Run: `mix test test/user_flows/ --max-failures 3`
Expected: All existing tests pass — the refactor is purely mechanical.

**Step 4: Commit**

```bash
git add lib/web/components/photo_gallery.ex lib/web/live/gallery_live/show.html.heex
git commit -m "refactor: extract photo_grid and lightbox into shared components"
```

---

### Task 3: Extract `Web.PhotoInteractions` from GalleryLive.Show

**Files:**
- Create: `lib/web/photo_interactions.ex`
- Modify: `lib/web/live/gallery_live/show.ex`

This task extracts the lightbox event-handling logic into a shared helper module, then updates GalleryLive.Show to delegate to it.

**Step 1: Create `Web.PhotoInteractions`**

Create `lib/web/photo_interactions.ex`:

```elixir
defmodule Web.PhotoInteractions do
  @moduledoc """
  Shared lightbox event handling for LiveViews that display photos.
  Both GalleryLive.Show and PersonLive.Show delegate to these functions.
  """

  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias Ancestry.Galleries
  alias Web.Comments.PhotoCommentsComponent

  @doc """
  Opens a photo in the lightbox. Loads photo and tagged people, pushes data to JS.
  """
  def open_photo(socket, photo_id) do
    photo = Galleries.get_photo!(photo_id)

    socket
    |> assign(:selected_photo, photo)
    |> assign(:photo_people, Galleries.list_photo_people(photo.id))
    |> push_photo_people()
  end

  @doc """
  Closes the lightbox and cleans up comment subscriptions.
  """
  def close_lightbox(socket) do
    socket
    |> cleanup_comments_subscription()
    |> assign(:selected_photo, nil)
  end

  @doc """
  Navigates to the next or previous photo in the lightbox.
  `photos_fn` is a zero-arity function that returns the ordered photo list.
  """
  def navigate_lightbox(socket, direction, photos_fn) do
    current = socket.assigns.selected_photo
    photos = photos_fn.()
    idx = Enum.find_index(photos, &(&1.id == current.id)) || 0

    next_idx =
      case direction do
        :next -> min(idx + 1, length(photos) - 1)
        :prev -> max(idx - 1, 0)
      end

    new_photo = Enum.at(photos, next_idx)

    socket
    |> assign(:selected_photo, new_photo)
    |> assign(:photo_people, Galleries.list_photo_people(new_photo.id))
    |> push_photo_people()
    |> resubscribe_comments(new_photo)
  end

  @doc """
  Selects a specific photo from the thumbnail strip.
  """
  def select_photo(socket, photo_id) do
    new_photo = Galleries.get_photo!(photo_id)

    socket
    |> assign(:selected_photo, new_photo)
    |> assign(:photo_people, Galleries.list_photo_people(new_photo.id))
    |> push_photo_people()
    |> resubscribe_comments(new_photo)
  end

  @doc """
  Toggles the side panel (people + comments). Manages comment PubSub subscription.
  """
  def toggle_panel(socket) do
    opening = not socket.assigns.panel_open

    if opening do
      topic = "photo_comments:#{socket.assigns.selected_photo.id}"

      if Phoenix.LiveView.connected?(socket) do
        Phoenix.PubSub.subscribe(Ancestry.PubSub, topic)
      end

      socket
      |> assign(:panel_open, true)
      |> assign(:comments_topic, topic)
    else
      cleanup_comments_subscription(socket)
    end
  end

  @doc """
  Tags a person in the currently selected photo at normalized coordinates.
  """
  def tag_person(socket, person_id, x, y) do
    photo = socket.assigns.selected_photo

    case Galleries.tag_person_in_photo(photo.id, String.to_integer(person_id), x, y) do
      {:ok, _} ->
        socket
        |> assign(:photo_people, Galleries.list_photo_people(photo.id))
        |> push_photo_people()

      {:error, _} ->
        socket
    end
  end

  @doc """
  Removes a person tag from a photo.
  """
  def untag_person(socket, photo_id, person_id) do
    :ok =
      Galleries.untag_person_from_photo(String.to_integer(photo_id), String.to_integer(person_id))

    socket
    |> assign(:photo_people, Galleries.list_photo_people(socket.assigns.selected_photo.id))
    |> push_photo_people()
  end

  @doc """
  Searches all people for tagging. Returns `{:reply, payload, socket}` tuple.
  """
  def search_people_for_tag(socket, query) do
    results =
      if String.length(query) >= 2 do
        Ancestry.People.search_all_people(query)
      else
        []
      end

    payload = %{
      results:
        Enum.map(results, fn p ->
          %{
            id: p.id,
            name: Ancestry.People.Person.display_name(p),
            has_photo: p.photo != nil && p.photo_status == "processed",
            photo_url:
              if(p.photo && p.photo_status == "processed",
                do: Ancestry.Uploaders.PersonPhoto.url({p.photo, p}, :thumbnail),
                else: nil
              )
          }
        end)
    }

    {payload, socket}
  end

  @doc """
  Pushes a highlight event for a person circle on the photo.
  """
  def highlight_person(socket, dom_id) do
    pp_id = dom_id |> String.replace("photo-person-", "") |> String.to_integer()
    pp = Enum.find(socket.assigns.photo_people, &(&1.id == pp_id))

    if pp do
      push_event(socket, "highlight_person", %{person_id: pp.person_id})
    else
      socket
    end
  end

  @doc """
  Pushes an unhighlight event for a person circle on the photo.
  """
  def unhighlight_person(socket, dom_id) do
    pp_id = dom_id |> String.replace("photo-person-", "") |> String.to_integer()
    pp = Enum.find(socket.assigns.photo_people, &(&1.id == pp_id))

    if pp do
      push_event(socket, "unhighlight_person", %{person_id: pp.person_id})
    else
      socket
    end
  end

  @doc """
  Handles comment PubSub messages by forwarding to the PhotoCommentsComponent.
  Returns `{:noreply, socket}`.
  """
  def handle_comment_info(socket, {:comment_created, comment}) do
    send_update(PhotoCommentsComponent, id: "photo-comments", comment_created: comment)
    {:noreply, socket}
  end

  def handle_comment_info(socket, {:comment_updated, comment}) do
    send_update(PhotoCommentsComponent, id: "photo-comments", comment_updated: comment)
    {:noreply, socket}
  end

  def handle_comment_info(socket, {:comment_deleted, comment}) do
    send_update(PhotoCommentsComponent, id: "photo-comments", comment_deleted: comment)
    {:noreply, socket}
  end

  # --- Private helpers ---

  def push_photo_people(socket) do
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

  defp cleanup_comments_subscription(socket) do
    if socket.assigns.comments_topic && Phoenix.LiveView.connected?(socket) do
      Phoenix.PubSub.unsubscribe(Ancestry.PubSub, socket.assigns.comments_topic)
    end

    socket
    |> assign(:panel_open, false)
    |> assign(:comments_topic, nil)
  end

  defp resubscribe_comments(socket, new_photo) do
    if socket.assigns.panel_open and Phoenix.LiveView.connected?(socket) do
      old_topic = socket.assigns.comments_topic
      new_topic = "photo_comments:#{new_photo.id}"

      if old_topic && old_topic != new_topic do
        Phoenix.PubSub.unsubscribe(Ancestry.PubSub, old_topic)
      end

      if old_topic != new_topic do
        Phoenix.PubSub.subscribe(Ancestry.PubSub, new_topic)
      end

      assign(socket, :comments_topic, new_topic)
    else
      socket
    end
  end
end
```

**Step 2: Update `GalleryLive.Show` to delegate to `PhotoInteractions`**

In `lib/web/live/gallery_live/show.ex`, add alias and replace the duplicated logic:

Add alias at top:
```elixir
alias Web.PhotoInteractions
```

Replace event handlers (keep gallery-specific ones like uploads, selection, delete):

```elixir
  # Replace photo_clicked (non-selection-mode branch):
  def handle_event("photo_clicked", %{"id" => id}, socket) do
    if socket.assigns.selection_mode do
      handle_event("toggle_photo_select", %{"id" => to_string(id)}, socket)
    else
      {:noreply, PhotoInteractions.open_photo(socket, id)}
    end
  end

  def handle_event("toggle_panel", _, socket) do
    {:noreply, PhotoInteractions.toggle_panel(socket)}
  end

  def handle_event("close_lightbox", _, socket) do
    {:noreply, PhotoInteractions.close_lightbox(socket)}
  end

  def handle_event("lightbox_keydown", %{"key" => "Escape"}, socket) do
    {:noreply, PhotoInteractions.close_lightbox(socket)}
  end

  def handle_event("lightbox_keydown", %{"key" => "ArrowRight"}, socket) do
    {:noreply,
     PhotoInteractions.navigate_lightbox(socket, :next, fn ->
       Galleries.list_photos(socket.assigns.gallery.id)
     end)}
  end

  def handle_event("lightbox_keydown", %{"key" => "ArrowLeft"}, socket) do
    {:noreply,
     PhotoInteractions.navigate_lightbox(socket, :prev, fn ->
       Galleries.list_photos(socket.assigns.gallery.id)
     end)}
  end

  def handle_event("lightbox_keydown", _, socket), do: {:noreply, socket}

  def handle_event("lightbox_select", %{"id" => id}, socket) do
    {:noreply, PhotoInteractions.select_photo(socket, String.to_integer(id))}
  end

  def handle_event("tag_person", %{"person_id" => person_id, "x" => x, "y" => y}, socket) do
    {:noreply, PhotoInteractions.tag_person(socket, person_id, x, y)}
  end

  def handle_event("untag_person", %{"photo-id" => photo_id, "person-id" => person_id}, socket) do
    {:noreply, PhotoInteractions.untag_person(socket, photo_id, person_id)}
  end

  def handle_event("highlight_person_on_photo", %{"id" => dom_id}, socket) do
    {:noreply, PhotoInteractions.highlight_person(socket, dom_id)}
  end

  def handle_event("unhighlight_person_on_photo", %{"id" => dom_id}, socket) do
    {:noreply, PhotoInteractions.unhighlight_person(socket, dom_id)}
  end

  def handle_event("search_people_for_tag", %{"query" => query}, socket) do
    {payload, socket} = PhotoInteractions.search_people_for_tag(socket, query)
    {:reply, payload, socket}
  end
```

Replace comment handle_info clauses:
```elixir
  def handle_info({:comment_created, _} = msg, socket),
    do: PhotoInteractions.handle_comment_info(socket, msg)

  def handle_info({:comment_updated, _} = msg, socket),
    do: PhotoInteractions.handle_comment_info(socket, msg)

  def handle_info({:comment_deleted, _} = msg, socket),
    do: PhotoInteractions.handle_comment_info(socket, msg)
```

Remove the now-unused private functions: `navigate_lightbox/2`, `push_photo_people/1`, `cleanup_comments_subscription/1`, `resubscribe_comments/2`.

**Step 3: Run tests to verify gallery still works**

Run: `mix test test/user_flows/ --max-failures 3`
Expected: All existing tests pass.

**Step 4: Commit**

```bash
git add lib/web/photo_interactions.ex lib/web/live/gallery_live/show.ex
git commit -m "refactor: extract shared photo interactions from gallery"
```

---

### Task 4: Add photo gallery to PersonLive.Show

**Files:**
- Modify: `lib/web/live/person_live/show.ex`
- Modify: `lib/web/live/person_live/show.html.heex`

**Step 1: Update PersonLive.Show mount to load photos and lightbox assigns**

In `lib/web/live/person_live/show.ex`, add alias:
```elixir
alias Ancestry.Galleries
alias Web.PhotoInteractions
```

In `mount/3`, after existing assigns, add:
```elixir
     |> assign(:selected_photo, nil)
     |> assign(:panel_open, false)
     |> assign(:photo_people, [])
     |> assign(:comments_topic, nil)
     |> load_person_photos(person)
```

Add the private helper:
```elixir
  defp load_person_photos(socket, person) do
    photos = Galleries.list_photos_for_person(person.id)

    socket
    |> assign(:person_photos, photos)
    |> assign(:person_photos_count, length(photos))
    |> stream(:person_photos, photos, reset: true)
  end
```

Note: We store the photo list in `@person_photos` (a regular assign) for the lightbox thumbnail strip and navigation, and also stream it for the masonry grid.

**Step 2: Add lightbox event handlers to PersonLive.Show**

Add these `handle_event` clauses to `lib/web/live/person_live/show.ex`:

```elixir
  # --- Photo gallery events ---

  def handle_event("photo_clicked", %{"id" => id}, socket) do
    {:noreply, PhotoInteractions.open_photo(socket, id)}
  end

  def handle_event("close_lightbox", _, socket) do
    {:noreply, PhotoInteractions.close_lightbox(socket)}
  end

  def handle_event("lightbox_keydown", %{"key" => "Escape"}, socket) do
    {:noreply, PhotoInteractions.close_lightbox(socket)}
  end

  def handle_event("lightbox_keydown", %{"key" => "ArrowRight"}, socket) do
    {:noreply,
     PhotoInteractions.navigate_lightbox(socket, :next, fn ->
       Galleries.list_photos_for_person(socket.assigns.person.id)
     end)}
  end

  def handle_event("lightbox_keydown", %{"key" => "ArrowLeft"}, socket) do
    {:noreply,
     PhotoInteractions.navigate_lightbox(socket, :prev, fn ->
       Galleries.list_photos_for_person(socket.assigns.person.id)
     end)}
  end

  def handle_event("lightbox_keydown", _, socket), do: {:noreply, socket}

  def handle_event("lightbox_select", %{"id" => id}, socket) do
    {:noreply, PhotoInteractions.select_photo(socket, String.to_integer(id))}
  end

  def handle_event("toggle_panel", _, socket) do
    {:noreply, PhotoInteractions.toggle_panel(socket)}
  end

  def handle_event("tag_person", %{"person_id" => person_id, "x" => x, "y" => y}, socket) do
    {:noreply, PhotoInteractions.tag_person(socket, person_id, x, y)}
  end

  def handle_event("untag_person", %{"photo-id" => photo_id, "person-id" => person_id}, socket) do
    {:noreply, PhotoInteractions.untag_person(socket, photo_id, person_id)}
  end

  def handle_event("highlight_person_on_photo", %{"id" => dom_id}, socket) do
    {:noreply, PhotoInteractions.highlight_person(socket, dom_id)}
  end

  def handle_event("unhighlight_person_on_photo", %{"id" => dom_id}, socket) do
    {:noreply, PhotoInteractions.unhighlight_person(socket, dom_id)}
  end

  def handle_event("search_people_for_tag", %{"query" => query}, socket) do
    {payload, socket} = PhotoInteractions.search_people_for_tag(socket, query)
    {:reply, payload, socket}
  end
```

Add comment PubSub forwarding:
```elixir
  def handle_info({:comment_created, _} = msg, socket),
    do: PhotoInteractions.handle_comment_info(socket, msg)

  def handle_info({:comment_updated, _} = msg, socket),
    do: PhotoInteractions.handle_comment_info(socket, msg)

  def handle_info({:comment_deleted, _} = msg, socket),
    do: PhotoInteractions.handle_comment_info(socket, msg)
```

**Step 3: Add photo gallery section to template**

In `lib/web/live/person_live/show.html.heex`, after the closing `</div>` of the relationships section (line 472) and before the `<% end %>` that closes the edit/detail conditional (line 473), add:

```heex
    <%!-- Tagged Photos Section --%>
    <%= if @person_photos_count > 0 do %>
      <div id="person-photos-section" class="max-w-7xl mx-auto mt-12">
        <div class="flex items-center gap-3 mb-6">
          <h2 class="text-xl font-bold text-base-content">Photos</h2>
          <span class="text-sm bg-base-200 text-base-content/60 px-2.5 py-0.5 rounded-full">
            {@person_photos_count}
          </span>
        </div>

        <Web.Components.PhotoGallery.photo_grid
          id="person-photo-grid"
          photos={@streams.person_photos}
        />
      </div>
    <% end %>

    <%!-- Lightbox (shared component) --%>
    <%= if @selected_photo do %>
      <Web.Components.PhotoGallery.lightbox
        selected_photo={@selected_photo}
        photos={@person_photos}
        panel_open={@panel_open}
        photo_people={@photo_people}
      />
    <% end %>
```

**Step 4: Run full test suite**

Run: `mix test --max-failures 5`
Expected: All tests pass.

**Step 5: Commit**

```bash
git add lib/web/live/person_live/show.ex lib/web/live/person_live/show.html.heex
git commit -m "feat: show tagged photos on person page with shared lightbox"
```

---

### Task 5: Write user flow test

**Files:**
- Create: `test/user_flows/person_photos_test.exs`

**Step 1: Write the test**

```elixir
defmodule Ancestry.UserFlows.PersonPhotosTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Ancestry.Families
  alias Ancestry.Galleries
  alias Ancestry.People

  # Given a person tagged in processed photos across galleries
  # When the user visits the person show page
  # Then the photos section shows with the tagged photos in a masonry grid
  #
  # When the user clicks a photo
  # Then the lightbox opens showing that photo
  #
  # When the user presses the right arrow
  # Then the lightbox navigates to the next tagged photo
  #
  # When the user presses Escape
  # Then the lightbox closes and the person show page is visible again

  setup do
    {:ok, family} = Families.create_family(%{name: "Test Family"})
    {:ok, gallery} = Galleries.create_gallery(%{name: "Summer 2024", family_id: family.id})
    {:ok, person} = People.create_person(family, %{given_name: "Alice", surname: "Smith"})

    # Create two processed photos
    {:ok, photo1} =
      Galleries.create_photo(%{
        gallery_id: gallery.id,
        original_path: "/tmp/test1.jpg",
        original_filename: "beach.jpg",
        content_type: "image/jpeg"
      })

    {:ok, photo1} = Galleries.update_photo_processed(photo1, "beach.jpg")

    {:ok, photo2} =
      Galleries.create_photo(%{
        gallery_id: gallery.id,
        original_path: "/tmp/test2.jpg",
        original_filename: "sunset.jpg",
        content_type: "image/jpeg"
      })

    {:ok, photo2} = Galleries.update_photo_processed(photo2, "sunset.jpg")

    # Tag person in both photos
    {:ok, _} = Galleries.tag_person_in_photo(photo1.id, person.id, 0.5, 0.5)
    {:ok, _} = Galleries.tag_person_in_photo(photo2.id, person.id, 0.3, 0.7)

    %{family: family, person: person, photo1: photo1, photo2: photo2}
  end

  test "person show page displays tagged photos and lightbox works", %{
    conn: conn,
    person: person,
    photo2: photo2
  } do
    {:ok, view, html} = live(conn, ~p"/people/#{person.id}")

    # Photos section is visible with count
    assert html =~ "Photos"
    assert has_element?(view, "#person-photos-section")
    assert has_element?(view, "#person-photo-grid")

    # Click a photo to open lightbox
    view |> element("#person-photo-grid div[phx-click]", "") |> render_click()
    assert has_element?(view, "#lightbox")

    # Close lightbox with Escape
    render_keydown(view, "lightbox_keydown", %{"key" => "Escape"})
    refute has_element?(view, "#lightbox")

    # Person show page is still visible
    assert has_element?(view, "#person-photos-section")
  end

  test "person with no tagged photos does not show photos section", %{conn: conn} do
    {:ok, family} = Families.create_family(%{name: "Another Family"})
    {:ok, person} = People.create_person(family, %{given_name: "Bob", surname: "Jones"})

    {:ok, _view, html} = live(conn, ~p"/people/#{person.id}")

    refute html =~ "person-photos-section"
  end
end
```

**Step 2: Run the test**

Run: `mix test test/user_flows/person_photos_test.exs --max-failures 3`
Expected: PASS

**Step 3: Commit**

```bash
git add test/user_flows/person_photos_test.exs
git commit -m "test: add person photos user flow test"
```

---

### Task 6: Run precommit and fix any issues

**Step 1: Run precommit**

Run: `mix precommit`
Expected: Compilation, formatting, and tests all pass.

**Step 2: Fix any issues found**

If warnings or failures, fix them and commit.

**Step 3: Final commit if needed**

```bash
git add -A
git commit -m "fix: address precommit issues"
```
