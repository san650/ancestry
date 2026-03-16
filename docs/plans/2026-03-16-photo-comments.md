# Photo Comments Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add anonymous comments to photos, displayed in a side panel within the lightbox, with real-time PubSub updates.

**Architecture:** New `Ancestry.Comments` context with `PhotoComment` schema. A `Web.Comments.PhotoCommentsComponent` LiveComponent manages the comments panel. The parent `GalleryLive.Show` handles PubSub subscriptions and forwards messages to the component via `send_update/2`. TDD throughout.

**Tech Stack:** Phoenix LiveView, Ecto, Phoenix PubSub, LiveComponent

**Design doc:** `docs/plans/2026-03-16-photo-comments-design.md`

---

### Task 1: Migration — create photo_comments table

**Files:**
- Create: `priv/repo/migrations/TIMESTAMP_create_photo_comments.exs` (via `mix ecto.gen.migration`)

**Step 1: Generate the migration**

Run: `mix ecto.gen.migration create_photo_comments`

**Step 2: Write the migration**

```elixir
defmodule Ancestry.Repo.Migrations.CreatePhotoComments do
  use Ecto.Migration

  def change do
    create table(:photo_comments) do
      add :text, :text, null: false
      add :photo_id, references(:photos, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:photo_comments, [:photo_id])
  end
end
```

**Step 3: Run the migration**

Run: `mix ecto.migrate`
Expected: Migration succeeds with no errors.

**Step 4: Commit**

```bash
git add priv/repo/migrations/*_create_photo_comments.exs
git commit -m "Add photo_comments migration"
```

---

### Task 2: PhotoComment schema

**Files:**
- Create: `lib/ancestry/comments/photo_comment.ex`

**Step 1: Write the failing test**

Create `test/ancestry/comments_test.exs`:

```elixir
defmodule Ancestry.CommentsTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.Comments
  alias Ancestry.Comments.PhotoComment

  describe "create_photo_comment/1" do
    test "creates a comment with valid attrs" do
      gallery = gallery_fixture()
      photo = photo_fixture(gallery)

      assert {:ok, %PhotoComment{} = comment} =
               Comments.create_photo_comment(%{text: "Nice photo!", photo_id: photo.id})

      assert comment.text == "Nice photo!"
      assert comment.photo_id == photo.id
    end
  end

  defp gallery_fixture(attrs \\ %{}) do
    family = family_fixture()

    {:ok, gallery} =
      attrs
      |> Enum.into(%{name: "Test Gallery", family_id: family.id})
      |> Ancestry.Galleries.create_gallery()

    gallery
  end

  defp family_fixture(attrs \\ %{}) do
    {:ok, family} =
      attrs
      |> Enum.into(%{name: "Test Family"})
      |> Ancestry.Families.create_family()

    family
  end

  defp photo_fixture(gallery) do
    tmp_dir = Path.join(System.tmp_dir!(), "comment_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    dest = Path.join(tmp_dir, "photo.jpg")
    File.cp!("test/fixtures/test_image.jpg", dest)

    {:ok, photo} =
      Ancestry.Galleries.create_photo(%{
        gallery_id: gallery.id,
        original_path: dest,
        original_filename: "photo.jpg",
        content_type: "image/jpeg"
      })

    photo
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ancestry/comments_test.exs`
Expected: FAIL — `Ancestry.Comments` module not found.

**Step 3: Write the schema**

Create `lib/ancestry/comments/photo_comment.ex`:

```elixir
defmodule Ancestry.Comments.PhotoComment do
  use Ecto.Schema
  import Ecto.Changeset

  schema "photo_comments" do
    field :text, :string
    belongs_to :photo, Ancestry.Galleries.Photo

    timestamps()
  end

  def changeset(comment, attrs) do
    comment
    |> cast(attrs, [:text])
    |> validate_required([:text])
    |> validate_length(:text, min: 1)
    |> foreign_key_constraint(:photo_id)
  end
end
```

**Step 4: Write the context with create function**

Create `lib/ancestry/comments.ex`:

```elixir
defmodule Ancestry.Comments do
  import Ecto.Query
  alias Ancestry.Repo
  alias Ancestry.Comments.PhotoComment

  def create_photo_comment(attrs) do
    %PhotoComment{}
    |> PhotoComment.changeset(attrs)
    |> Ecto.Changeset.put_change(:photo_id, attrs[:photo_id] || attrs["photo_id"])
    |> Repo.insert()
    |> case do
      {:ok, comment} ->
        comment = Repo.preload(comment, :photo)

        Phoenix.PubSub.broadcast(
          Ancestry.PubSub,
          "photo_comments:#{comment.photo_id}",
          {:comment_created, comment}
        )

        {:ok, comment}

      error ->
        error
    end
  end
end
```

**Step 5: Run test to verify it passes**

Run: `mix test test/ancestry/comments_test.exs`
Expected: PASS

**Step 6: Commit**

```bash
git add lib/ancestry/comments/photo_comment.ex lib/ancestry/comments.ex test/ancestry/comments_test.exs
git commit -m "Add PhotoComment schema and create function"
```

---

### Task 3: Remaining context CRUD + validation tests

**Files:**
- Modify: `lib/ancestry/comments.ex`
- Modify: `test/ancestry/comments_test.exs`

**Step 1: Write failing tests for validation, list, update, delete**

Add to `test/ancestry/comments_test.exs`:

```elixir
describe "create_photo_comment/1 validations" do
  test "rejects empty text" do
    gallery = gallery_fixture()
    photo = photo_fixture(gallery)

    assert {:error, changeset} =
             Comments.create_photo_comment(%{text: "", photo_id: photo.id})

    assert "can't be blank" in errors_on(changeset).text
  end

  test "rejects nil text" do
    gallery = gallery_fixture()
    photo = photo_fixture(gallery)

    assert {:error, changeset} =
             Comments.create_photo_comment(%{photo_id: photo.id})

    assert "can't be blank" in errors_on(changeset).text
  end
end

describe "list_photo_comments/1" do
  test "returns comments ordered oldest first" do
    gallery = gallery_fixture()
    photo = photo_fixture(gallery)

    {:ok, first} = Comments.create_photo_comment(%{text: "First", photo_id: photo.id})
    {:ok, second} = Comments.create_photo_comment(%{text: "Second", photo_id: photo.id})

    comments = Comments.list_photo_comments(photo.id)
    assert [%{id: id1}, %{id: id2}] = comments
    assert id1 == first.id
    assert id2 == second.id
  end

  test "returns empty list when no comments" do
    gallery = gallery_fixture()
    photo = photo_fixture(gallery)

    assert [] == Comments.list_photo_comments(photo.id)
  end

  test "only returns comments for the given photo" do
    gallery = gallery_fixture()
    photo1 = photo_fixture(gallery)
    photo2 = photo_fixture(gallery)

    {:ok, _} = Comments.create_photo_comment(%{text: "On photo 1", photo_id: photo1.id})
    {:ok, _} = Comments.create_photo_comment(%{text: "On photo 2", photo_id: photo2.id})

    assert [comment] = Comments.list_photo_comments(photo1.id)
    assert comment.text == "On photo 1"
  end
end

describe "get_photo_comment!/1" do
  test "returns the comment" do
    gallery = gallery_fixture()
    photo = photo_fixture(gallery)
    {:ok, comment} = Comments.create_photo_comment(%{text: "Hello", photo_id: photo.id})

    fetched = Comments.get_photo_comment!(comment.id)
    assert fetched.id == comment.id
    assert fetched.text == "Hello"
  end
end

describe "update_photo_comment/2" do
  test "updates text" do
    gallery = gallery_fixture()
    photo = photo_fixture(gallery)
    {:ok, comment} = Comments.create_photo_comment(%{text: "Original", photo_id: photo.id})

    assert {:ok, updated} = Comments.update_photo_comment(comment, %{text: "Edited"})
    assert updated.text == "Edited"
  end

  test "rejects empty text on update" do
    gallery = gallery_fixture()
    photo = photo_fixture(gallery)
    {:ok, comment} = Comments.create_photo_comment(%{text: "Original", photo_id: photo.id})

    assert {:error, changeset} = Comments.update_photo_comment(comment, %{text: ""})
    assert "can't be blank" in errors_on(changeset).text
  end
end

describe "delete_photo_comment/1" do
  test "deletes the comment" do
    gallery = gallery_fixture()
    photo = photo_fixture(gallery)
    {:ok, comment} = Comments.create_photo_comment(%{text: "Delete me", photo_id: photo.id})

    assert {:ok, _} = Comments.delete_photo_comment(comment)
    assert_raise Ecto.NoResultsError, fn -> Comments.get_photo_comment!(comment.id) end
  end
end

describe "cascade delete" do
  test "deleting a photo deletes its comments" do
    gallery = gallery_fixture()
    photo = photo_fixture(gallery)
    {:ok, comment} = Comments.create_photo_comment(%{text: "Cascade me", photo_id: photo.id})

    {:ok, _} = Ancestry.Galleries.delete_photo(photo)
    assert_raise Ecto.NoResultsError, fn -> Comments.get_photo_comment!(comment.id) end
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/ancestry/comments_test.exs`
Expected: FAIL — `list_photo_comments`, `get_photo_comment!`, `update_photo_comment`, `delete_photo_comment` not defined.

**Step 3: Implement remaining context functions**

Add to `lib/ancestry/comments.ex`:

```elixir
def list_photo_comments(photo_id) do
  Repo.all(
    from c in PhotoComment,
      where: c.photo_id == ^photo_id,
      order_by: [asc: c.inserted_at, asc: c.id]
  )
end

def get_photo_comment!(id), do: Repo.get!(PhotoComment, id)

def update_photo_comment(%PhotoComment{} = comment, attrs) do
  comment
  |> PhotoComment.changeset(attrs)
  |> Repo.update()
  |> case do
    {:ok, comment} ->
      Phoenix.PubSub.broadcast(
        Ancestry.PubSub,
        "photo_comments:#{comment.photo_id}",
        {:comment_updated, comment}
      )

      {:ok, comment}

    error ->
      error
  end
end

def delete_photo_comment(%PhotoComment{} = comment) do
  Repo.delete(comment)
  |> case do
    {:ok, comment} ->
      Phoenix.PubSub.broadcast(
        Ancestry.PubSub,
        "photo_comments:#{comment.photo_id}",
        {:comment_deleted, comment}
      )

      {:ok, comment}

    error ->
      error
  end
end

def change_photo_comment(%PhotoComment{} = comment, attrs \\ %{}) do
  PhotoComment.changeset(comment, attrs)
end
```

**Step 4: Run tests to verify they pass**

Run: `mix test test/ancestry/comments_test.exs`
Expected: All PASS

**Step 5: Commit**

```bash
git add lib/ancestry/comments.ex test/ancestry/comments_test.exs
git commit -m "Add list, get, update, delete for photo comments"
```

---

### Task 4: Add has_many association to Photo schema

**Files:**
- Modify: `lib/ancestry/galleries/photo.ex:6-13`

**Step 1: Add the association**

In `lib/ancestry/galleries/photo.ex`, add inside the `schema` block after `belongs_to :gallery`:

```elixir
has_many :photo_comments, Ancestry.Comments.PhotoComment
```

**Step 2: Run all tests to verify nothing broke**

Run: `mix test`
Expected: All PASS

**Step 3: Commit**

```bash
git add lib/ancestry/galleries/photo.ex
git commit -m "Add has_many :photo_comments to Photo schema"
```

---

### Task 5: PhotoCommentsComponent — render existing comments

**Files:**
- Create: `lib/web/live/comments/photo_comments_component.ex`
- Create: `test/web/live/comments/photo_comments_component_test.exs`

**Step 1: Write the failing test**

Create `test/web/live/comments/photo_comments_component_test.exs`:

```elixir
defmodule Web.Comments.PhotoCommentsComponentTest do
  use Web.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Ancestry.Comments
  alias Ancestry.Galleries

  describe "rendering" do
    test "shows existing comments for a photo", %{conn: conn} do
      family = family_fixture()
      gallery = gallery_fixture(family)
      photo = photo_fixture(gallery)

      {:ok, _} = Comments.create_photo_comment(%{text: "Great shot!", photo_id: photo.id})
      {:ok, _} = Comments.create_photo_comment(%{text: "Love it", photo_id: photo.id})

      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/galleries/#{gallery.id}")

      # Open lightbox by clicking the photo
      view |> element("#photos-#{photo.id}") |> render_click()

      # Open comments panel
      view |> element("#toggle-comments-btn") |> render_click()

      assert has_element?(view, "#photo-comments-panel")
      assert has_element?(view, "#photo-comments-panel", "Great shot!")
      assert has_element?(view, "#photo-comments-panel", "Love it")
    end

    test "shows empty state when no comments", %{conn: conn} do
      family = family_fixture()
      gallery = gallery_fixture(family)
      photo = photo_fixture(gallery)

      {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/galleries/#{gallery.id}")

      view |> element("#photos-#{photo.id}") |> render_click()
      view |> element("#toggle-comments-btn") |> render_click()

      assert has_element?(view, "#photo-comments-panel")
      assert has_element?(view, "#comments-empty")
    end
  end

  defp family_fixture(attrs \\ %{}) do
    {:ok, family} =
      attrs
      |> Enum.into(%{name: "Test Family"})
      |> Ancestry.Families.create_family()

    family
  end

  defp gallery_fixture(family, attrs \\ %{}) do
    {:ok, gallery} =
      attrs
      |> Enum.into(%{name: "Test Gallery", family_id: family.id})
      |> Galleries.create_gallery()

    gallery
  end

  defp photo_fixture(gallery) do
    tmp_dir = Path.join(System.tmp_dir!(), "comment_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)
    dest = Path.join(tmp_dir, "photo.jpg")
    File.cp!("test/fixtures/test_image.jpg", dest)

    {:ok, photo} =
      Galleries.create_photo(%{
        gallery_id: gallery.id,
        original_path: dest,
        original_filename: "photo.jpg",
        content_type: "image/jpeg"
      })

    # Mark as processed so it shows in the grid as clickable
    {:ok, photo} = Galleries.update_photo_processed(photo, "photo.jpg")
    photo
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/web/live/comments/photo_comments_component_test.exs`
Expected: FAIL — no `#toggle-comments-btn` element.

**Step 3: Create the LiveComponent**

Create `lib/web/live/comments/photo_comments_component.ex`:

```elixir
defmodule Web.Comments.PhotoCommentsComponent do
  use Web, :live_component

  alias Ancestry.Comments

  @impl true
  def update(%{photo_id: photo_id} = assigns, socket) do
    old_topic = socket.assigns[:subscribed_topic]
    new_topic = "photo_comments:#{photo_id}"

    if old_topic && old_topic != new_topic do
      Phoenix.PubSub.unsubscribe(Ancestry.PubSub, old_topic)
    end

    if old_topic != new_topic do
      Phoenix.PubSub.subscribe(Ancestry.PubSub, new_topic)
    end

    comments = Comments.list_photo_comments(photo_id)
    changeset = Comments.change_photo_comment(%Comments.PhotoComment{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:subscribed_topic, new_topic)
     |> assign(:editing_comment_id, nil)
     |> assign(:edit_form, nil)
     |> assign(:form, to_form(changeset))
     |> stream(:comments, comments, reset: true)}
  end

  @impl true
  def update(%{comment_created: comment}, socket) do
    {:ok, stream_insert(socket, :comments, comment)}
  end

  def update(%{comment_updated: comment}, socket) do
    {:ok, stream_insert(socket, :comments, comment)}
  end

  def update(%{comment_deleted: comment}, socket) do
    {:ok, stream_delete(socket, :comments, comment)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="photo-comments-panel" class="flex flex-col h-full bg-white/5 rounded-xl">
      <div class="flex items-center justify-between px-4 py-3 border-b border-white/10">
        <h3 class="text-sm font-semibold text-white">Comments</h3>
        <button
          phx-click="close_comments"
          phx-target={@myself}
          class="p-1 text-white/40 hover:text-white rounded transition-colors"
        >
          <.icon name="hero-x-mark" class="w-4 h-4" />
        </button>
      </div>

      <div id="comments-list" phx-update="stream" class="flex-1 overflow-y-auto px-4 py-3 space-y-3">
        <div id="comments-empty" class="hidden only:block text-center py-8 text-white/30 text-sm">
          No comments yet
        </div>
        <div
          :for={{id, comment} <- @streams.comments}
          id={id}
          class="group rounded-lg bg-white/5 px-3 py-2"
        >
          <%= if @editing_comment_id == comment.id do %>
            <.form
              for={@edit_form}
              id={"edit-comment-#{comment.id}"}
              phx-submit="save_edit"
              phx-target={@myself}
              class="flex flex-col gap-2"
            >
              <input type="hidden" name="comment_id" value={comment.id} />
              <textarea
                name={@edit_form[:text].name}
                class="w-full bg-white/10 text-white text-sm rounded-lg px-3 py-2 border border-white/20 focus:border-primary focus:outline-none resize-none"
                rows="2"
              >{@edit_form[:text].value}</textarea>
              <div class="flex gap-2 justify-end">
                <button
                  type="button"
                  phx-click="cancel_edit"
                  phx-target={@myself}
                  class="px-2 py-1 text-xs text-white/50 hover:text-white transition-colors"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="px-2 py-1 text-xs bg-primary text-primary-content rounded font-medium hover:bg-primary/90 transition-colors"
                >
                  Save
                </button>
              </div>
            </.form>
          <% else %>
            <p class="text-sm text-white/80 whitespace-pre-wrap break-words">{comment.text}</p>
            <div class="flex items-center justify-between mt-1">
              <time class="text-xs text-white/30">
                {Calendar.strftime(comment.inserted_at, "%b %d, %Y %H:%M")}
              </time>
              <div class="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                <button
                  phx-click="edit_comment"
                  phx-value-id={comment.id}
                  phx-target={@myself}
                  class="p-1 text-white/30 hover:text-white rounded transition-colors"
                >
                  <.icon name="hero-pencil-square" class="w-3.5 h-3.5" />
                </button>
                <button
                  phx-click="delete_comment"
                  phx-value-id={comment.id}
                  phx-target={@myself}
                  class="p-1 text-white/30 hover:text-error rounded transition-colors"
                >
                  <.icon name="hero-trash" class="w-3.5 h-3.5" />
                </button>
              </div>
            </div>
          <% end %>
        </div>
      </div>

      <div class="px-4 py-3 border-t border-white/10">
        <.form for={@form} id="new-comment-form" phx-submit="save_comment" phx-target={@myself} class="flex gap-2">
          <input
            type="text"
            name={@form[:text].name}
            value={@form[:text].value}
            placeholder="Add a comment..."
            class="flex-1 bg-white/10 text-white text-sm rounded-lg px-3 py-2 border border-white/10 focus:border-primary focus:outline-none placeholder-white/30"
            autocomplete="off"
          />
          <button
            type="submit"
            class="px-3 py-2 bg-primary text-primary-content rounded-lg text-sm font-medium hover:bg-primary/90 transition-colors"
          >
            <.icon name="hero-paper-airplane" class="w-4 h-4" />
          </button>
        </.form>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("save_comment", %{"text" => text}, socket) do
    case Comments.create_photo_comment(%{text: text, photo_id: socket.assigns.photo_id}) do
      {:ok, _comment} ->
        changeset = Comments.change_photo_comment(%Comments.PhotoComment{})
        {:noreply, assign(socket, :form, to_form(changeset))}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  def handle_event("edit_comment", %{"id" => id}, socket) do
    comment = Comments.get_photo_comment!(String.to_integer(id))
    changeset = Comments.change_photo_comment(comment, %{text: comment.text})

    {:noreply,
     socket
     |> assign(:editing_comment_id, comment.id)
     |> assign(:edit_form, to_form(changeset))
     |> stream_insert(:comments, comment)}
  end

  def handle_event("save_edit", %{"comment_id" => id, "text" => text}, socket) do
    comment = Comments.get_photo_comment!(String.to_integer(id))

    case Comments.update_photo_comment(comment, %{text: text}) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> assign(:editing_comment_id, nil)
         |> assign(:edit_form, nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, :edit_form, to_form(changeset))}
    end
  end

  def handle_event("cancel_edit", _, socket) do
    {:noreply,
     socket
     |> assign(:editing_comment_id, nil)
     |> assign(:edit_form, nil)}
  end

  def handle_event("delete_comment", %{"id" => id}, socket) do
    comment = Comments.get_photo_comment!(String.to_integer(id))
    {:ok, _} = Comments.delete_photo_comment(comment)
    {:noreply, socket}
  end

  def handle_event("close_comments", _, socket) do
    send(self(), {:close_comments})
    {:noreply, socket}
  end
end
```

**Step 4: Run test to verify it still fails (no lightbox integration yet)**

Run: `mix test test/web/live/comments/photo_comments_component_test.exs`
Expected: FAIL — no `#toggle-comments-btn` in lightbox yet.

**Step 5: Commit (component only, tests still failing — that's expected)**

```bash
git add lib/web/live/comments/photo_comments_component.ex test/web/live/comments/photo_comments_component_test.exs
git commit -m "Add PhotoCommentsComponent skeleton and tests"
```

---

### Task 6: Integrate comments panel into the lightbox

**Files:**
- Modify: `lib/web/live/gallery_live/show.ex`
- Modify: `lib/web/live/gallery_live/show.html.heex`

**Step 1: Add assigns and events to `GalleryLive.Show`**

In `lib/web/live/gallery_live/show.ex`:

1. Add alias at top (after existing alias):
```elixir
alias Web.Comments.PhotoCommentsComponent
```

2. In `mount/3`, add to the assign chain (after `assign(:selected_photo, nil)`):
```elixir
|> assign(:comments_open, false)
```

3. Add new event handlers (after the `lightbox_select` handler):
```elixir
def handle_event("toggle_comments", _, socket) do
  comments_open = !socket.assigns.comments_open
  photo = socket.assigns.selected_photo

  socket =
    if comments_open and photo do
      Phoenix.PubSub.subscribe(Ancestry.PubSub, "photo_comments:#{photo.id}")
      assign(socket, :comments_topic, "photo_comments:#{photo.id}")
    else
      if topic = socket.assigns[:comments_topic] do
        Phoenix.PubSub.unsubscribe(Ancestry.PubSub, topic)
      end

      assign(socket, :comments_topic, nil)
    end

  {:noreply, assign(socket, :comments_open, comments_open)}
end
```

4. Modify `close_lightbox` to also close comments:
```elixir
def handle_event("close_lightbox", _, socket) do
  if topic = socket.assigns[:comments_topic] do
    Phoenix.PubSub.unsubscribe(Ancestry.PubSub, topic)
  end

  {:noreply,
   socket
   |> assign(:selected_photo, nil)
   |> assign(:comments_open, false)
   |> assign(:comments_topic, nil)}
end
```

5. Update `lightbox_keydown` Escape handler similarly:
```elixir
def handle_event("lightbox_keydown", %{"key" => "Escape"}, socket) do
  if topic = socket.assigns[:comments_topic] do
    Phoenix.PubSub.unsubscribe(Ancestry.PubSub, topic)
  end

  {:noreply,
   socket
   |> assign(:selected_photo, nil)
   |> assign(:comments_open, false)
   |> assign(:comments_topic, nil)}
end
```

6. Update `lightbox_select` and `navigate_lightbox` to resubscribe when comments are open. In `navigate_lightbox/2`, after setting `selected_photo`, add PubSub topic swap:
```elixir
defp navigate_lightbox(socket, direction) do
  current = socket.assigns.selected_photo
  photos = Galleries.list_photos(socket.assigns.gallery.id)
  idx = Enum.find_index(photos, &(&1.id == current.id)) || 0

  next_idx =
    case direction do
      :next -> min(idx + 1, length(photos) - 1)
      :prev -> max(idx - 1, 0)
    end

  next_photo = Enum.at(photos, next_idx)
  socket = assign(socket, :selected_photo, next_photo)

  if socket.assigns.comments_open and next_photo.id != current.id do
    if old_topic = socket.assigns[:comments_topic] do
      Phoenix.PubSub.unsubscribe(Ancestry.PubSub, old_topic)
    end

    new_topic = "photo_comments:#{next_photo.id}"
    Phoenix.PubSub.subscribe(Ancestry.PubSub, new_topic)
    assign(socket, :comments_topic, new_topic)
  else
    socket
  end
end
```

Similarly update `lightbox_select`:
```elixir
def handle_event("lightbox_select", %{"id" => id}, socket) do
  old_photo = socket.assigns.selected_photo
  new_photo = Galleries.get_photo!(String.to_integer(id))
  socket = assign(socket, :selected_photo, new_photo)

  if socket.assigns.comments_open and new_photo.id != old_photo.id do
    if old_topic = socket.assigns[:comments_topic] do
      Phoenix.PubSub.unsubscribe(Ancestry.PubSub, old_topic)
    end

    new_topic = "photo_comments:#{new_photo.id}"
    Phoenix.PubSub.subscribe(Ancestry.PubSub, new_topic)
    {:noreply, assign(socket, :comments_topic, new_topic)}
  else
    {:noreply, socket}
  end
end
```

7. Add PubSub forwarding handlers (after existing `handle_info` clauses):
```elixir
def handle_info({:comment_created, comment}, socket) do
  send_update(PhotoCommentsComponent,
    id: "photo-comments-#{socket.assigns.selected_photo.id}",
    comment_created: comment
  )

  {:noreply, socket}
end

def handle_info({:comment_updated, comment}, socket) do
  send_update(PhotoCommentsComponent,
    id: "photo-comments-#{socket.assigns.selected_photo.id}",
    comment_updated: comment
  )

  {:noreply, socket}
end

def handle_info({:comment_deleted, comment}, socket) do
  send_update(PhotoCommentsComponent,
    id: "photo-comments-#{socket.assigns.selected_photo.id}",
    comment_deleted: comment
  )

  {:noreply, socket}
end

def handle_info({:close_comments}, socket) do
  if topic = socket.assigns[:comments_topic] do
    Phoenix.PubSub.unsubscribe(Ancestry.PubSub, topic)
  end

  {:noreply,
   socket
   |> assign(:comments_open, false)
   |> assign(:comments_topic, nil)}
end
```

**Step 2: Update the lightbox template**

In `lib/web/live/gallery_live/show.html.heex`, modify the lightbox section (lines 347-428):

1. Add a comments toggle button in the lightbox top bar (inside the `div` with download and close buttons, before the close button):
```heex
<button
  id="toggle-comments-btn"
  phx-click="toggle_comments"
  class={[
    "p-2 rounded-lg transition-colors",
    if(@comments_open,
      do: "text-primary bg-white/10",
      else: "text-white/50 hover:text-white hover:bg-white/10"
    )
  ]}
  title="Toggle comments"
>
  <.icon name="hero-chat-bubble-left-right" class="w-5 h-5" />
</button>
```

2. Wrap the main image area and add comments panel. Replace the main image `div` (line 377) with a flex container that splits between image and comments:

```heex
<div class="flex-1 flex min-h-0">
  <%!-- Main image area --%>
  <div class={[
    "flex-1 flex items-center justify-center relative min-h-0 px-16",
    @comments_open && "lg:flex-[2]"
  ]}>
    <button
      phx-click={JS.push("lightbox_keydown", value: %{key: "ArrowLeft"})}
      class="absolute left-3 p-3 text-white/40 hover:text-white hover:bg-white/10 rounded-full transition-colors z-10"
    >
      <.icon name="hero-chevron-left" class="w-7 h-7" />
    </button>

    <img
      src={Ancestry.Uploaders.Photo.url({@selected_photo.image, @selected_photo}, :large)}
      alt={@selected_photo.original_filename}
      class="max-h-full max-w-full object-contain rounded-lg shadow-2xl"
    />

    <button
      phx-click={JS.push("lightbox_keydown", value: %{key: "ArrowRight"})}
      class="absolute right-3 p-3 text-white/40 hover:text-white hover:bg-white/10 rounded-full transition-colors z-10"
    >
      <.icon name="hero-chevron-right" class="w-7 h-7" />
    </button>
  </div>

  <%!-- Comments panel --%>
  <%= if @comments_open do %>
    <div class="hidden lg:flex w-80 shrink-0 border-l border-white/10">
      <.live_component
        module={Web.Comments.PhotoCommentsComponent}
        id={"photo-comments-#{@selected_photo.id}"}
        photo_id={@selected_photo.id}
      />
    </div>
  <% end %>
</div>
```

**Step 3: Run the component tests**

Run: `mix test test/web/live/comments/photo_comments_component_test.exs`
Expected: All PASS

**Step 4: Run all tests to check for regressions**

Run: `mix test`
Expected: All PASS

**Step 5: Commit**

```bash
git add lib/web/live/gallery_live/show.ex lib/web/live/gallery_live/show.html.heex
git commit -m "Integrate comments panel into lightbox"
```

---

### Task 7: Component interaction tests — create, edit, delete

**Files:**
- Modify: `test/web/live/comments/photo_comments_component_test.exs`

**Step 1: Add interaction tests**

Add to the test file:

```elixir
describe "creating comments" do
  test "submitting the form creates a comment", %{conn: conn} do
    family = family_fixture()
    gallery = gallery_fixture(family)
    photo = photo_fixture(gallery)

    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/galleries/#{gallery.id}")

    view |> element("#photos-#{photo.id}") |> render_click()
    view |> element("#toggle-comments-btn") |> render_click()

    view
    |> form("#new-comment-form", %{text: "Beautiful photo!"})
    |> render_submit()

    assert has_element?(view, "#photo-comments-panel", "Beautiful photo!")
  end
end

describe "editing comments" do
  test "edit and save updates the comment", %{conn: conn} do
    family = family_fixture()
    gallery = gallery_fixture(family)
    photo = photo_fixture(gallery)
    {:ok, comment} = Comments.create_photo_comment(%{text: "Original", photo_id: photo.id})

    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/galleries/#{gallery.id}")

    view |> element("#photos-#{photo.id}") |> render_click()
    view |> element("#toggle-comments-btn") |> render_click()

    # Click edit
    view |> element("[phx-click='edit_comment'][phx-value-id='#{comment.id}']") |> render_click()

    assert has_element?(view, "#edit-comment-#{comment.id}")

    # Submit edit
    view
    |> form("#edit-comment-#{comment.id}", %{text: "Edited text"})
    |> render_submit()

    assert has_element?(view, "#photo-comments-panel", "Edited text")
    refute has_element?(view, "#edit-comment-#{comment.id}")
  end
end

describe "deleting comments" do
  test "clicking delete removes the comment", %{conn: conn} do
    family = family_fixture()
    gallery = gallery_fixture(family)
    photo = photo_fixture(gallery)
    {:ok, comment} = Comments.create_photo_comment(%{text: "Delete me", photo_id: photo.id})

    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/galleries/#{gallery.id}")

    view |> element("#photos-#{photo.id}") |> render_click()
    view |> element("#toggle-comments-btn") |> render_click()

    assert has_element?(view, "#photo-comments-panel", "Delete me")

    view |> element("[phx-click='delete_comment'][phx-value-id='#{comment.id}']") |> render_click()

    refute has_element?(view, "#photo-comments-panel", "Delete me")
  end
end
```

**Step 2: Run tests**

Run: `mix test test/web/live/comments/photo_comments_component_test.exs`
Expected: All PASS (implementation already exists from Task 5)

**Step 3: Commit**

```bash
git add test/web/live/comments/photo_comments_component_test.exs
git commit -m "Add interaction tests for comments: create, edit, delete"
```

---

### Task 8: GalleryLive.Show integration tests

**Files:**
- Modify: `test/web/live/comments/photo_comments_component_test.exs`

**Step 1: Add integration tests**

Add to the test file:

```elixir
describe "lightbox integration" do
  test "toggle button opens and closes comments panel", %{conn: conn} do
    family = family_fixture()
    gallery = gallery_fixture(family)
    photo = photo_fixture(gallery)

    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/galleries/#{gallery.id}")

    view |> element("#photos-#{photo.id}") |> render_click()

    refute has_element?(view, "#photo-comments-panel")

    view |> element("#toggle-comments-btn") |> render_click()
    assert has_element?(view, "#photo-comments-panel")

    view |> element("#toggle-comments-btn") |> render_click()
    refute has_element?(view, "#photo-comments-panel")
  end

  test "closing lightbox closes comments panel", %{conn: conn} do
    family = family_fixture()
    gallery = gallery_fixture(family)
    photo = photo_fixture(gallery)

    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/galleries/#{gallery.id}")

    view |> element("#photos-#{photo.id}") |> render_click()
    view |> element("#toggle-comments-btn") |> render_click()

    assert has_element?(view, "#photo-comments-panel")

    # Close lightbox
    view |> element("[phx-click='close_lightbox']") |> render_click()

    refute has_element?(view, "#lightbox")
    refute has_element?(view, "#photo-comments-panel")
  end

  test "navigating photos reloads comments", %{conn: conn} do
    family = family_fixture()
    gallery = gallery_fixture(family)
    photo1 = photo_fixture(gallery)
    photo2 = photo_fixture(gallery)

    {:ok, _} = Comments.create_photo_comment(%{text: "Comment on photo 1", photo_id: photo1.id})
    {:ok, _} = Comments.create_photo_comment(%{text: "Comment on photo 2", photo_id: photo2.id})

    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/galleries/#{gallery.id}")

    # Open lightbox on photo 1 and open comments
    view |> element("#photos-#{photo1.id}") |> render_click()
    view |> element("#toggle-comments-btn") |> render_click()

    assert has_element?(view, "#photo-comments-panel", "Comment on photo 1")
    refute has_element?(view, "#photo-comments-panel", "Comment on photo 2")

    # Navigate to photo 2 via thumbnail strip
    view |> element("[phx-click='lightbox_select'][phx-value-id='#{photo2.id}']") |> render_click()

    assert has_element?(view, "#photo-comments-panel", "Comment on photo 2")
    refute has_element?(view, "#photo-comments-panel", "Comment on photo 1")
  end
end

describe "real-time updates" do
  test "PubSub broadcast adds new comment to panel", %{conn: conn} do
    family = family_fixture()
    gallery = gallery_fixture(family)
    photo = photo_fixture(gallery)

    {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/galleries/#{gallery.id}")

    view |> element("#photos-#{photo.id}") |> render_click()
    view |> element("#toggle-comments-btn") |> render_click()

    # Simulate a comment arriving from another user via PubSub
    {:ok, comment} = Comments.create_photo_comment(%{text: "From another user", photo_id: photo.id})

    # The PubSub broadcast from create_photo_comment is delivered to the LiveView
    # which forwards it to the component via send_update
    # Give it a moment to process
    assert render(view) =~ "From another user"
  end
end
```

**Step 2: Run tests**

Run: `mix test test/web/live/comments/photo_comments_component_test.exs`
Expected: All PASS

**Step 3: Commit**

```bash
git add test/web/live/comments/photo_comments_component_test.exs
git commit -m "Add lightbox integration and real-time tests for comments"
```

---

### Task 9: Run precommit and fix any issues

**Step 1: Run precommit**

Run: `mix precommit`
Expected: Compile (warnings-as-errors), format, tests all pass.

**Step 2: Fix any issues found**

Address any compilation warnings, formatting issues, or test failures.

**Step 3: Commit fixes if any**

```bash
git add -A
git commit -m "Fix precommit issues for photo comments"
```
