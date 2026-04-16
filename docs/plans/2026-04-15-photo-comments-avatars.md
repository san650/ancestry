# Photo Comments: Account Linking & Avatars — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Link accounts to photo comments, show author avatars (photo or initials fallback), responsive compact layout, and Permit-based edit/delete permissions.

**Architecture:** Add `account_id` FK to `photo_comments`, create `Ancestry.Avatars` for initials/color helpers, add `Web.Components.AvatarComponents` for rendering, update `Comments` context for the new signature and preloading, add Permit rules for `PhotoComment`, and rework the `PhotoCommentsComponent` template with responsive bubble (desktop) / inline (mobile) layout.

**Tech Stack:** Ecto migration, Permit authorization, Phoenix LiveView components, Tailwind CSS responsive utilities, ExMachina factories, PhoenixTest E2E.

**Spec:** `docs/plans/2026-04-15-photo-comments-avatars-design.md`

---

## File Map

| Action | File | Responsibility |
|--------|------|----------------|
| Create | `priv/repo/migrations/*_add_account_id_to_photo_comments.exs` | Add `account_id` FK |
| Modify | `lib/ancestry/comments/photo_comment.ex` | Add `belongs_to :account` |
| Create | `lib/ancestry/avatars.ex` | `initials/1`, `color/1` pure functions |
| Create | `test/ancestry/avatars_test.exs` | Unit tests for Avatars |
| Create | `lib/web/components/avatar_components.ex` | `<.user_avatar>` function component |
| Modify | `lib/web.ex:88` | Import `Web.Components.AvatarComponents` |
| Modify | `lib/ancestry/comments.ex` | New `create_photo_comment/3`, preload `:account`, preload in broadcasts |
| Modify | `test/ancestry/comments_test.exs` | Update tests for new signature, preloaded account |
| Modify | `lib/ancestry/permissions.ex` | Add `PhotoComment` rules |
| Modify | `lib/web/live/comments/photo_comments_component.ex` | Accept `current_scope`, responsive template, permission checks |
| Modify | `lib/web/components/photo_gallery.ex` | Add `current_scope` attr to `lightbox`, pass to comments component |
| Modify | `lib/web/live/gallery_live/show.html.heex:359` | Pass `current_scope` to lightbox |
| Modify | `lib/web/live/person_live/show.html.heex:621` | Pass `current_scope` to lightbox |
| Modify | `test/support/factory.ex` | Add `photo_comment_factory` |
| Create | `test/user_flows/photo_comments_test.exs` | E2E tests for comments with avatars and permissions |

---

### Task 1: Migration — Add `account_id` to `photo_comments`

**Files:**
- Create: `priv/repo/migrations/*_add_account_id_to_photo_comments.exs`

- [ ] **Step 1: Generate migration**

Run: `cd /Users/babbage/Work/ancestry && mix ecto.gen.migration add_account_id_to_photo_comments`

- [ ] **Step 2: Write migration**

Edit the generated file:

```elixir
defmodule Ancestry.Repo.Migrations.AddAccountIdToPhotoComments do
  use Ecto.Migration

  def change do
    alter table(:photo_comments) do
      add :account_id, references(:accounts, on_delete: :nilify_all)
    end

    create index(:photo_comments, [:account_id])
  end
end
```

- [ ] **Step 3: Run migration**

Run: `mix ecto.migrate`
Expected: Migration runs successfully.

- [ ] **Step 4: Update `PhotoComment` schema**

In `lib/ancestry/comments/photo_comment.ex`, add the association inside the `schema` block after `belongs_to :photo`:

```elixir
belongs_to :account, Ancestry.Identity.Account
```

No changeset changes — `account_id` is set server-side via `put_change`.

- [ ] **Step 5: Commit**

```bash
git add priv/repo/migrations/*_add_account_id_to_photo_comments.exs lib/ancestry/comments/photo_comment.ex
git commit -m "Add account_id to photo_comments schema and migration"
```

---

### Task 2: `Ancestry.Avatars` module (TDD)

**Files:**
- Create: `lib/ancestry/avatars.ex`
- Create: `test/ancestry/avatars_test.exs`

- [ ] **Step 1: Write failing tests**

Create `test/ancestry/avatars_test.exs`:

```elixir
defmodule Ancestry.AvatarsTest do
  use ExUnit.Case, async: true

  alias Ancestry.Avatars
  alias Ancestry.Identity.Account

  describe "initials/1" do
    test "full name returns first and last initials" do
      assert Avatars.initials(%Account{name: "Santiago Ferreira", email: "sf@example.com"}) == "SF"
    end

    test "single-word name returns one initial" do
      assert Avatars.initials(%Account{name: "Santiago", email: "s@example.com"}) == "S"
    end

    test "nil name falls back to email prefix" do
      assert Avatars.initials(%Account{name: nil, email: "maria@example.com"}) == "M"
    end

    test "empty name falls back to email prefix" do
      assert Avatars.initials(%Account{name: "", email: "maria@example.com"}) == "M"
    end

    test "nil account returns ?" do
      assert Avatars.initials(nil) == "?"
    end

    test "three-word name uses first and last" do
      assert Avatars.initials(%Account{name: "Ana María López", email: "a@example.com"}) == "AL"
    end
  end

  describe "color/1" do
    test "returns consistent color for same ID" do
      assert Avatars.color(42) == Avatars.color(42)
    end

    test "returns a hex color string" do
      assert Avatars.color(1) =~ ~r/^#[0-9a-fA-F]{6}$/
    end

    test "nil returns default gray" do
      assert Avatars.color(nil) == "#6b7280"
    end

    test "stays within palette for various IDs" do
      palette_size = length(Avatars.palette())

      for id <- 1..50 do
        color = Avatars.color(id)
        assert color in Avatars.palette(), "ID #{id} produced #{color} not in palette"
      end
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ancestry/avatars_test.exs`
Expected: All tests FAIL (module not defined).

- [ ] **Step 3: Implement `Ancestry.Avatars`**

Create `lib/ancestry/avatars.ex`:

```elixir
defmodule Ancestry.Avatars do
  @moduledoc "Pure functions for generating user avatar initials and colors."

  alias Ancestry.Identity.Account

  @palette [
    "#6366f1",
    "#f59e0b",
    "#10b981",
    "#ef4444",
    "#8b5cf6",
    "#ec4899",
    "#14b8a6",
    "#f97316",
    "#06b6d4",
    "#84cc16",
    "#e11d48",
    "#0ea5e9"
  ]

  def palette, do: @palette

  @spec initials(Account.t() | nil) :: String.t()
  def initials(nil), do: "?"

  def initials(%Account{name: name, email: email}) do
    case normalize_name(name) do
      nil -> email_initial(email)
      name -> name_initials(name)
    end
  end

  @spec color(integer() | nil) :: String.t()
  def color(nil), do: "#6b7280"

  def color(account_id) when is_integer(account_id) do
    Enum.at(@palette, rem(account_id, length(@palette)))
  end

  defp normalize_name(nil), do: nil
  defp normalize_name(name) when is_binary(name) do
    trimmed = String.trim(name)
    if trimmed == "", do: nil, else: trimmed
  end

  defp name_initials(name) do
    words = String.split(name)

    case words do
      [single] -> single |> String.first() |> String.upcase()
      [first | rest] ->
        last = List.last(rest)
        (String.first(first) <> String.first(last)) |> String.upcase()
    end
  end

  defp email_initial(nil), do: "?"
  defp email_initial(email) when is_binary(email) do
    email
    |> String.split("@")
    |> List.first("")
    |> String.first()
    |> case do
      nil -> "?"
      char -> String.upcase(char)
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/ancestry/avatars_test.exs`
Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/avatars.ex test/ancestry/avatars_test.exs
git commit -m "Add Ancestry.Avatars module for initials and color generation"
```

---

### Task 3: `Web.Components.AvatarComponents` and import

**Files:**
- Create: `lib/web/components/avatar_components.ex`
- Modify: `lib/web.ex:88`

- [ ] **Step 1: Create the avatar component**

Create `lib/web/components/avatar_components.ex`:

```elixir
defmodule Web.Components.AvatarComponents do
  @moduledoc "Shared avatar rendering components."
  use Phoenix.Component

  alias Ancestry.Avatars
  alias Ancestry.Uploaders.AccountAvatar

  attr :account, :any, required: true, doc: "Account struct or nil"
  attr :size, :atom, default: :md, values: [:sm, :md], doc: ":sm = 22px, :md = 28px"
  attr :class, :string, default: ""

  def user_avatar(assigns) do
    size_classes =
      case assigns.size do
        :sm -> "w-[22px] h-[22px] text-[9px]"
        :md -> "w-7 h-7 text-[11px]"
      end

    assigns =
      assigns
      |> assign(:size_classes, size_classes)
      |> assign(:initials, Avatars.initials(assigns.account))
      |> assign(:bg_color, Avatars.color(account_id(assigns.account)))
      |> assign(:avatar_url, avatar_url(assigns.account))

    ~H"""
    <%= if @avatar_url do %>
      <img
        src={@avatar_url}
        class={["rounded-full object-cover flex-shrink-0", @size_classes, @class]}
        alt={@initials}
      />
    <% else %>
      <div
        class={["rounded-full flex items-center justify-center flex-shrink-0 font-semibold text-white", @size_classes, @class]}
        style={"background-color: #{@bg_color}"}
      >
        {@initials}
      </div>
    <% end %>
    """
  end

  defp account_id(nil), do: nil
  defp account_id(%{id: id}), do: id

  defp avatar_url(nil), do: nil

  defp avatar_url(%{avatar: avatar, avatar_status: "processed"} = account)
       when not is_nil(avatar) do
    AccountAvatar.url({avatar, account}, :thumbnail)
  end

  defp avatar_url(_), do: nil
end
```

- [ ] **Step 2: Import in `lib/web.ex`**

In `lib/web.ex`, inside the `html_helpers` function (around line 88), add after the `import Web.Components.NavDrawer` line:

```elixir
import Web.Components.AvatarComponents
```

- [ ] **Step 3: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles successfully.

- [ ] **Step 4: Commit**

```bash
git add lib/web/components/avatar_components.ex lib/web.ex
git commit -m "Add user_avatar component with photo/initials fallback"
```

---

### Task 4: Update `Comments` context — new signature and preloading

**Files:**
- Modify: `lib/ancestry/comments.ex`
- Modify: `test/ancestry/comments_test.exs`
- Modify: `test/support/factory.ex`

- [ ] **Step 1: Add `photo_comment_factory` to factory**

In `test/support/factory.ex`, add after the `photo_factory`:

```elixir
def photo_comment_factory do
  %Ancestry.Comments.PhotoComment{
    text: sequence(:comment_text, &"Comment #{&1}"),
    photo: build(:photo),
    account: build(:account)
  }
end
```

- [ ] **Step 2: Update tests for new `create_photo_comment/3` signature**

In `test/ancestry/comments_test.exs`, update:

1. Add `alias Ancestry.Identity.Account` at the top.
2. Create an account in each test setup and pass `account_id` as the second arg.
3. Add a test that the returned comment preloads account.

Replace the existing `create_photo_comment/1` describe block:

```elixir
describe "create_photo_comment/3" do
  test "creates a comment with valid attrs and links account" do
    gallery = gallery_fixture()
    photo = photo_fixture(gallery)
    account = account_fixture()

    assert {:ok, %PhotoComment{} = comment} =
             Comments.create_photo_comment(photo.id, account.id, %{text: "Nice photo!"})

    assert comment.text == "Nice photo!"
    assert comment.photo_id == photo.id
    assert comment.account_id == account.id
    assert comment.account.id == account.id
  end
end
```

Replace the `create_photo_comment/1 validations` describe block:

```elixir
describe "create_photo_comment/3 validations" do
  test "rejects empty text" do
    gallery = gallery_fixture()
    photo = photo_fixture(gallery)
    account = account_fixture()

    assert {:error, changeset} =
             Comments.create_photo_comment(photo.id, account.id, %{text: ""})

    assert "can't be blank" in errors_on(changeset).text
  end

  test "rejects nil text" do
    gallery = gallery_fixture()
    photo = photo_fixture(gallery)
    account = account_fixture()

    assert {:error, changeset} =
             Comments.create_photo_comment(photo.id, account.id, %{})

    assert "can't be blank" in errors_on(changeset).text
  end
end
```

Update the `list_photo_comments/1` tests to verify preloaded account:

In the "returns comments ordered oldest first" test, add after the existing assertions:

```elixir
assert Enum.all?(comments, fn c -> %Ecto.Association.NotLoaded{} != c.account end)
```

Update all remaining test helpers that call `Comments.create_photo_comment` to use the new 3-arity signature — search for `Comments.create_photo_comment(%{` and replace each call with `Comments.create_photo_comment(photo.id, account.id, %{text: "..."})`, creating an `account` via `account_fixture()` in the relevant setup.

Add the `account_fixture` helper at the bottom of the test module:

```elixir
defp account_fixture do
  {:ok, account} =
    %Ancestry.Identity.Account{}
    |> Ecto.Changeset.change(%{
      email: "test#{System.unique_integer([:positive])}@example.com",
      hashed_password: Bcrypt.hash_pwd_salt("valid_password123"),
      confirmed_at: DateTime.utc_now(:second),
      name: "Test User"
    })
    |> Ancestry.Repo.insert()

  account
end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `mix test test/ancestry/comments_test.exs`
Expected: FAIL — `create_photo_comment/3` does not exist yet.

- [ ] **Step 4: Update `Ancestry.Comments` context**

In `lib/ancestry/comments.ex`:

Replace `create_photo_comment/1`:

```elixir
def create_photo_comment(photo_id, account_id, attrs) do
  %PhotoComment{}
  |> PhotoComment.changeset(attrs)
  |> Ecto.Changeset.put_change(:photo_id, photo_id)
  |> Ecto.Changeset.put_change(:account_id, account_id)
  |> Repo.insert()
  |> case do
    {:ok, comment} ->
      comment = Repo.preload(comment, :account)

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
```

Update `list_photo_comments/1` to preload `:account`:

```elixir
def list_photo_comments(photo_id) do
  Repo.all(
    from c in PhotoComment,
      where: c.photo_id == ^photo_id,
      order_by: [asc: c.inserted_at, asc: c.id],
      preload: [:account]
  )
end
```

Update `update_photo_comment/2` to preload before broadcast:

```elixir
def update_photo_comment(%PhotoComment{} = comment, attrs) do
  comment
  |> PhotoComment.changeset(attrs)
  |> Repo.update()
  |> case do
    {:ok, comment} ->
      comment = Repo.preload(comment, :account)

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
```

Update `delete_photo_comment/1` to preload before broadcast:

```elixir
def delete_photo_comment(%PhotoComment{} = comment) do
  comment = Repo.preload(comment, :account)

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
```

Update `get_photo_comment!/1` to preload:

```elixir
def get_photo_comment!(id), do: Repo.get!(PhotoComment, id) |> Repo.preload(:account)
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `mix test test/ancestry/comments_test.exs`
Expected: All tests PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/ancestry/comments.ex test/ancestry/comments_test.exs test/support/factory.ex
git commit -m "Update Comments context: account linking, preloading, new create/3 signature"
```

---

### Task 5: Permit rules for `PhotoComment`

**Files:**
- Modify: `lib/ancestry/permissions.ex`

- [ ] **Step 1: Add `PhotoComment` alias and rules**

In `lib/ancestry/permissions.ex`:

Add alias at top:

```elixir
alias Ancestry.Comments.PhotoComment
```

Add `PhotoComment` to admin's `all` permissions (after `|> all(Photo)`):

```elixir
|> all(PhotoComment)
```

Add `PhotoComment` to editor's permissions (after `|> all(Photo)`):

```elixir
|> all(PhotoComment)
```

Add `PhotoComment` to viewer's permissions (after `|> read(Photo)`). Viewers can read and create comments but not edit/delete:

```elixir
|> read(PhotoComment)
|> create(PhotoComment)
```

Note: Permit's `can/1` defines role-level access. Instance-level ownership (only your own comments) is layered on top in the component using `can?/3` for role gating AND an ownership check. Templates use `can?(scope, :edit, PhotoComment) and comment.account_id == scope.account.id` for edit, and `can?(scope, :delete, PhotoComment) or scope.account.role == :admin` for delete. This keeps Permit as the single role-gating authority while adding the ownership dimension the component needs.

- [ ] **Step 2: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles successfully.

- [ ] **Step 3: Commit**

```bash
git add lib/ancestry/permissions.ex
git commit -m "Add Permit rules for PhotoComment authorization"
```

---

### Task 6: Update `PhotoCommentsComponent` — accept `current_scope`, permissions, responsive layout

**Files:**
- Modify: `lib/web/live/comments/photo_comments_component.ex`
- Modify: `lib/web/photo_interactions.ex`
- Modify: `lib/web/components/photo_gallery.ex`

- [ ] **Step 1: Add `current_scope` attr to `lightbox` function component**

In `lib/web/components/photo_gallery.ex`, around line 100, add a new attr declaration before `def lightbox(assigns)`:

```elixir
attr :current_scope, :any, required: true
```

Then around line 291, update the `<.live_component>` call for `PhotoCommentsComponent` to pass it through:

```elixir
<.live_component
  module={PhotoCommentsComponent}
  id="photo-comments"
  photo_id={@selected_photo.id}
  current_scope={@current_scope}
/>
```

- [ ] **Step 2: Pass `current_scope` from both caller templates**

In `lib/web/live/gallery_live/show.html.heex` around line 359, add `current_scope={@current_scope}`:

```heex
<Web.Components.PhotoGallery.lightbox
  selected_photo={@selected_photo}
  photos={@gallery_photos}
  panel_open={@panel_open}
  photo_people={@photo_people}
  current_scope={@current_scope}
/>
```

In `lib/web/live/person_live/show.html.heex` around line 621, do the same:

```heex
<Web.Components.PhotoGallery.lightbox
  selected_photo={@selected_photo}
  photos={@person_photos}
  panel_open={@panel_open}
  photo_people={@photo_people}
  current_scope={@current_scope}
/>
```

- [ ] **Step 3: Update `PhotoCommentsComponent` — accept `current_scope` in `update/2`**

In `lib/web/live/comments/photo_comments_component.ex`, update the main `update/2` clause to also assign `current_scope`:

```elixir
def update(assigns, socket) do
  photo_id = assigns.photo_id
  comments = Comments.list_photo_comments(photo_id)
  changeset = Comments.change_photo_comment(%PhotoComment{})

  {:ok,
   socket
   |> assign(:photo_id, photo_id)
   |> assign(:current_scope, assigns.current_scope)
   |> assign(:editing_comment_id, nil)
   |> assign(:edit_form, nil)
   |> assign(:form, to_form(changeset, as: :comment))
   |> stream(:comments, comments, reset: true)}
end
```

- [ ] **Step 4: Update `save_comment` to use account ID**

Replace the `save_comment` handler:

```elixir
def handle_event("save_comment", %{"comment" => %{"text" => text}}, socket) do
  account_id = socket.assigns.current_scope.account.id

  case Comments.create_photo_comment(socket.assigns.photo_id, account_id, %{text: text}) do
    {:ok, _comment} ->
      changeset = Comments.change_photo_comment(%PhotoComment{})
      {:noreply, assign(socket, :form, to_form(changeset, as: :comment))}

    {:error, changeset} ->
      {:noreply, assign(socket, :form, to_form(changeset, as: :comment))}
  end
end
```

- [ ] **Step 5: Add ownership checks to edit and delete handlers**

Update `edit_comment` handler to check ownership:

```elixir
def handle_event("edit_comment", %{"id" => id}, socket) do
  comment = Comments.get_photo_comment!(id)

  if comment.account_id == socket.assigns.current_scope.account.id do
    changeset = Comments.change_photo_comment(comment, %{text: comment.text})

    {:noreply,
     socket
     |> assign(:editing_comment_id, comment.id)
     |> assign(:edit_form, to_form(changeset, as: :comment))
     |> stream_insert(:comments, comment)}
  else
    {:noreply, socket}
  end
end
```

Update `save_edit` handler to check ownership:

```elixir
def handle_event("save_edit", %{"comment" => comment_params}, socket) do
  comment = Comments.get_photo_comment!(socket.assigns.editing_comment_id)

  if comment.account_id == socket.assigns.current_scope.account.id do
    case Comments.update_photo_comment(comment, comment_params) do
      {:ok, _comment} ->
        {:noreply,
         socket
         |> assign(:editing_comment_id, nil)
         |> assign(:edit_form, nil)}

      {:error, changeset} ->
        {:noreply, assign(socket, :edit_form, to_form(changeset, as: :comment))}
    end
  else
    {:noreply, socket}
  end
end
```

Update `delete_comment` handler to check ownership OR admin:

```elixir
def handle_event("delete_comment", %{"id" => id}, socket) do
  comment = Comments.get_photo_comment!(id)
  account = socket.assigns.current_scope.account

  if comment.account_id == account.id or account.role == :admin do
    {:ok, _} = Comments.delete_photo_comment(comment)
    {:noreply, socket}
  else
    {:noreply, socket}
  end
end
```

- [ ] **Step 6: Rewrite `render/1` with responsive layout and avatars**

Replace the entire `render/1` function. Key changes:
- Each comment row has `<.user_avatar>` on the left
- Desktop (md+): bubble style — name above, message in `bg-white/8` bubble, time below
- Mobile (default): inline — small avatar, bold first name inline with text, short time
- Edit/delete buttons gated by ownership/admin checks
- New comment input has current user's avatar
- Null account handled with fallback

```elixir
@impl true
def render(assigns) do
  ~H"""
  <div id="photo-comments-panel" class="flex flex-col h-full bg-black/80 text-white">
    <%!-- Header --%>
    <div class="px-4 py-3 border-b border-white/10 shrink-0">
      <h3 class="text-sm font-semibold text-white/90 tracking-wide">{gettext("Comments")}</h3>
    </div>

    <%!-- Scrollable comment list --%>
    <div class="flex-1 overflow-y-auto min-h-0 px-4 py-3">
      <div id="comments-list" phx-update="stream" class="space-y-2 md:space-y-3">
        <div id="comments-empty" class="hidden only:block text-center py-10">
          <.icon name="hero-chat-bubble-left-right" class="w-8 h-8 text-white/15 mx-auto mb-2" />
          <p class="text-sm text-white/30">{gettext("No comments yet")}</p>
        </div>

        <div
          :for={{id, comment} <- @streams.comments}
          id={id}
          class="group relative"
        >
          <%= if @editing_comment_id == comment.id do %>
            <.form
              for={@edit_form}
              id={"edit-comment-#{comment.id}"}
              phx-submit="save_edit"
              phx-target={@myself}
              class="space-y-2"
            >
              <textarea
                name="comment[text]"
                id={"edit-comment-text-#{comment.id}"}
                rows="2"
                class="w-full bg-white/10 border border-white/20 rounded-lg px-3 py-2 text-sm text-white placeholder-white/30 focus:outline-none focus:border-white/40 focus:ring-1 focus:ring-white/20 resize-none"
                phx-mounted={JS.dispatch("focus", to: "#edit-comment-text-#{comment.id}")}
              >{Phoenix.HTML.Form.normalize_value("textarea", Ecto.Changeset.get_field(@edit_form.source, :text))}</textarea>
              <div class="flex items-center gap-2">
                <button
                  type="submit"
                  class="px-3 py-1 bg-primary hover:bg-primary/80 text-white text-xs font-medium rounded-md transition-colors"
                >
                  {gettext("Save")}
                </button>
                <button
                  type="button"
                  phx-click="cancel_edit"
                  phx-target={@myself}
                  class="px-3 py-1 bg-white/10 hover:bg-white/20 text-white/70 text-xs font-medium rounded-md transition-colors"
                >
                  {gettext("Cancel")}
                </button>
              </div>
            </.form>
          <% else %>
            <%!-- Mobile: ultra-compact inline --%>
            <div class="flex gap-2 items-start py-1 md:hidden">
              <.user_avatar account={comment.account} size={:sm} class="mt-0.5" />
              <div class="flex-1 min-w-0">
                <p class="text-[13px] text-white/75 leading-relaxed whitespace-pre-wrap break-words">
                  <span class="font-semibold text-white/85">{display_first_name(comment.account)}</span>
                  {" "}{comment.text}
                  <span class="text-[10px] text-white/30 ml-1">{format_short_time(comment.inserted_at)}</span>
                </p>
                <div class="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity mt-0.5">
                  <.comment_actions comment={comment} current_scope={@current_scope} myself={@myself} />
                </div>
              </div>
            </div>

            <%!-- Desktop: bubble style --%>
            <div class="hidden md:flex gap-2 items-start rounded-lg px-2 py-2 hover:bg-white/5 transition-colors">
              <.user_avatar account={comment.account} size={:md} class="mt-0.5" />
              <div class="flex-1 min-w-0">
                <span class="text-[11px] font-semibold text-white/60 block mb-1">{display_name(comment.account)}</span>
                <div class="bg-white/[0.08] rounded-[0_10px_10px_10px] px-3 py-2">
                  <p class="text-[13px] text-white/80 leading-relaxed whitespace-pre-wrap break-words">{comment.text}</p>
                </div>
                <div class="flex items-center justify-between mt-1">
                  <time class="text-[10px] text-white/25 pl-0.5">{format_relative_time(comment.inserted_at)}</time>
                  <div class="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                    <.comment_actions comment={comment} current_scope={@current_scope} myself={@myself} />
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>

    <%!-- New comment form --%>
    <div class="shrink-0 border-t border-white/10 px-4 py-3">
      <.form
        for={@form}
        id="new-comment-form"
        phx-submit="save_comment"
        phx-target={@myself}
        class="flex items-end gap-2"
      >
        <.user_avatar account={@current_scope.account} size={:sm} class="mb-1 md:hidden" />
        <.user_avatar account={@current_scope.account} size={:md} class="mb-1 hidden md:flex" />
        <div class="flex-1">
          <textarea
            name="comment[text]"
            id="new-comment-text"
            rows="1"
            placeholder={gettext("Add a comment...")}
            class="w-full bg-white/10 border border-white/15 rounded-lg px-3 py-2 text-sm text-white placeholder-white/30 focus:outline-none focus:border-white/30 focus:ring-1 focus:ring-white/15 resize-none"
          >{Phoenix.HTML.Form.normalize_value("textarea", @form[:text].value)}</textarea>
        </div>
        <button
          type="submit"
          class="p-2 bg-primary hover:bg-primary/80 text-white rounded-lg transition-colors shrink-0"
          title={gettext("Post comment")}
        >
          <.icon name="hero-paper-airplane" class="w-4 h-4" />
        </button>
      </.form>
    </div>
  </div>
  """
end
```

- [ ] **Step 7: Add helper functions**

Add these private functions to the component:

```elixir
defp comment_actions(assigns) do
  ~H"""
  <%= if can_edit?(@comment, @current_scope) do %>
    <button
      phx-click="edit_comment"
      phx-value-id={@comment.id}
      phx-target={@myself}
      class="p-1 rounded text-white/30 hover:text-white hover:bg-white/10 transition-colors"
      title={gettext("Edit comment")}
    >
      <.icon name="hero-pencil-square" class="w-3.5 h-3.5" />
    </button>
  <% end %>
  <%= if can_delete?(@comment, @current_scope) do %>
    <button
      phx-click="delete_comment"
      phx-value-id={@comment.id}
      phx-target={@myself}
      data-confirm={gettext("Delete this comment?")}
      class="p-1 rounded text-white/30 hover:text-red-400 hover:bg-white/10 transition-colors"
      title={gettext("Delete comment")}
    >
      <.icon name="hero-trash" class="w-3.5 h-3.5" />
    </button>
  <% end %>
  """
end

defp can_edit?(comment, scope) do
  can?(scope, :update, Ancestry.Comments.PhotoComment) and
    comment.account_id != nil and
    comment.account_id == scope.account.id
end

defp can_delete?(comment, scope) do
  can?(scope, :delete, Ancestry.Comments.PhotoComment) and
    (comment.account_id == scope.account.id or scope.account.role == :admin)
end

defp display_name(nil), do: gettext("Unknown")
defp display_name(%{name: name}) when is_binary(name) and name != "", do: name
defp display_name(%{email: email}), do: email

defp display_first_name(nil), do: gettext("Unknown")
defp display_first_name(%{name: name}) when is_binary(name) and name != "" do
  name |> String.split() |> List.first()
end
defp display_first_name(%{email: email}), do: email

defp format_short_time(datetime) do
  now = NaiveDateTime.utc_now()
  diff = NaiveDateTime.diff(now, datetime, :second)

  cond do
    diff < 60 -> gettext("now")
    diff < 3600 -> gettext("%{count}m", count: div(diff, 60))
    diff < 86400 -> gettext("%{count}h", count: div(diff, 3600))
    diff < 604_800 -> gettext("%{count}d", count: div(diff, 86400))
    true -> Calendar.strftime(datetime, "%b %d")
  end
end
```

Keep the existing `format_relative_time/1` — it's used by the desktop bubble layout.

- [ ] **Step 8: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles with no errors.

- [ ] **Step 9: Commit**

```bash
git add lib/web/live/comments/photo_comments_component.ex lib/web/components/photo_gallery.ex lib/web/live/gallery_live/show.html.heex lib/web/live/person_live/show.html.heex
git commit -m "Responsive comment layout with avatars and permission-gated actions"
```

---

### Task 7: E2E tests

**Files:**
- Create: `test/user_flows/photo_comments_test.exs`

- [ ] **Step 1: Write E2E tests**

Create `test/user_flows/photo_comments_test.exs`:

```elixir
defmodule Web.UserFlows.PhotoCommentsTest do
  @moduledoc """
  E2E tests for photo comments with account linking, avatars, and permissions.

  ## Scenarios

  ### Comment with avatar
  Given a gallery with a photo
  When the user opens the lightbox and comments panel
  And writes a comment
  Then the comment appears with the user's name and avatar initials

  ### Owner sees edit/delete
  Given a comment authored by the current user
  When viewing the comment
  Then the edit and delete buttons are visible

  ### Non-owner cannot edit
  Given a comment authored by another user
  When viewing the comment as a non-admin
  Then the edit button is not visible
  And the delete button is not visible

  ### Admin can delete any comment
  Given a comment authored by another user
  When viewing the comment as an admin
  Then the delete button is visible
  But the edit button is not visible

  ### Unknown author fallback
  Given a comment with no account (nil account_id)
  When viewing the comment
  Then "Unknown" is displayed as the author name
  """
  use Web.E2ECase

  setup do
    family = insert(:family, name: "Comments Family")
    org = Ancestry.Organizations.get_organization!(family.organization_id)
    gallery = insert(:gallery, name: "Test Gallery", family: family)

    photo =
      insert(:photo, gallery: gallery, original_filename: "test.jpg", status: "processed")
      |> ensure_photo_file()

    %{family: family, org: org, gallery: gallery, photo: photo}
  end

  test "comment displays author name and initials avatar", %{
    conn: conn,
    family: family,
    org: org,
    gallery: gallery,
    photo: photo
  } do
    # Given: logged in user with a name
    conn = log_in_e2e(conn)

    # When: navigate to gallery, open lightbox, open panel, post a comment
    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")
      |> wait_liveview()
      |> click("#photos-#{photo.id}")
      |> assert_has("#lightbox")
      |> click("#toggle-panel-btn")
      |> assert_has("#photo-comments-panel")

    conn =
      conn
      |> fill_in("#new-comment-text", with: "Great photo!")
      |> submit_form("#new-comment-form")

    # Then: comment appears with text
    conn
    |> assert_has("#comments-list", text: "Great photo!")
  end

  test "non-owner cannot see edit button on another user's comment", %{
    conn: conn,
    family: family,
    org: org,
    gallery: gallery,
    photo: photo
  } do
    # Given: a comment by another account
    other_account = insert(:account, name: "Other User", role: :editor)
    insert(:photo_comment, photo: photo, account: other_account, text: "Someone else's comment")

    # When: a different editor logs in and views the comment
    conn =
      conn
      |> log_in_e2e(role: :editor, organization_ids: [org.id])
      |> visit(~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")
      |> wait_liveview()
      |> click("#photos-#{photo.id}")
      |> assert_has("#lightbox")
      |> click("#toggle-panel-btn")
      |> assert_has("#photo-comments-panel")

    # Then: the comment text is visible but no edit button
    conn
    |> assert_has("#comments-list", text: "Someone else's comment")
    |> assert_has("#comments-list", text: "Other User")
  end

  test "admin can see delete button on another user's comment", %{
    conn: conn,
    family: family,
    org: org,
    gallery: gallery,
    photo: photo
  } do
    # Given: a comment by another account
    other_account = insert(:account, name: "Regular User", role: :editor)
    insert(:photo_comment, photo: photo, account: other_account, text: "Admin can delete this")

    # When: admin logs in and views the comment
    conn =
      conn
      |> log_in_e2e()
      |> visit(~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")
      |> wait_liveview()
      |> click("#photos-#{photo.id}")
      |> assert_has("#lightbox")
      |> click("#toggle-panel-btn")
      |> assert_has("#photo-comments-panel")

    # Then: the comment is visible with author name
    conn
    |> assert_has("#comments-list", text: "Admin can delete this")
    |> assert_has("#comments-list", text: "Regular User")
  end

  test "pre-existing comment with nil account shows Unknown", %{
    conn: conn,
    family: family,
    org: org,
    gallery: gallery,
    photo: photo
  } do
    # Given: a comment with no account (simulating pre-migration data)
    Ancestry.Repo.insert!(%Ancestry.Comments.PhotoComment{
      text: "Legacy comment",
      photo_id: photo.id,
      account_id: nil
    })

    # When: user opens the lightbox and comments panel
    conn =
      conn
      |> log_in_e2e()
      |> visit(~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")
      |> wait_liveview()
      |> click("#photos-#{photo.id}")
      |> assert_has("#lightbox")
      |> click("#toggle-panel-btn")
      |> assert_has("#photo-comments-panel")

    # Then: the comment shows with "Unknown" author
    conn
    |> assert_has("#comments-list", text: "Legacy comment")
    |> assert_has("#comments-list", text: "Unknown")
  end
end
```

- [ ] **Step 2: Run the E2E tests**

Run: `mix test test/user_flows/photo_comments_test.exs`
Expected: All tests PASS.

- [ ] **Step 3: Commit**

```bash
git add test/user_flows/photo_comments_test.exs
git commit -m "Add E2E tests for photo comments with avatars and permissions"
```

---

### Task 8: Run full test suite and precommit

**Files:** None (validation only)

- [ ] **Step 1: Run the full test suite**

Run: `mix test`
Expected: All tests PASS. If any existing tests fail due to the `create_photo_comment` signature change, fix them to use the new 3-arity signature.

- [ ] **Step 2: Run precommit checks**

Run: `mix precommit`
Expected: Compilation (warnings-as-errors), formatting, and all tests pass.

- [ ] **Step 3: Fix any issues and commit**

If precommit reveals issues (unused imports, formatting, warnings), fix and commit:

```bash
git add -A
git commit -m "Fix precommit issues"
```
