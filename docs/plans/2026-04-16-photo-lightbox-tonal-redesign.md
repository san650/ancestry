# Photo Lightbox Side Panel — Tonal Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the lightbox side panel's border-based section dividers with a 4-step dark tonal scale (`bg-white/[0.03]` → `[0.16]`), restore readable empty states (text-white/50), and unify the panel header to "Photo info" — on both desktop side-panel and mobile full-screen layouts.

**Architecture:** Pure visual refactor. No schema, route, context, PubSub, or Oban changes. Surfaces touched: the `lightbox/1` panel branch in `lib/web/components/photo_gallery.ex` and the entire template of `lib/web/live/comments/photo_comments_component.ex`. Each section becomes an inline tonal "card" — no shared function component (the pattern recurs only twice; abstracting now would be premature). New `test_id`s expose the cards to E2E tests.

**Tech Stack:** Phoenix v1.8 LiveView, Tailwind v4, Heroicons via `<.icon>`, PhoenixTest.Playwright for E2E.

**Spec:** `docs/plans/2026-04-16-photo-lightbox-tonal-redesign-design.md`

## Relevant learnings

Before touching code, hold these `docs/learnings.jsonl` entries in mind. They have all bitten this codebase before.

| ID | Why it applies here |
|---|---|
| `stable-livecomponent-ids` | The Comments live component MUST keep its stable `id="photo-comments"`. Don't derive it from `@selected_photo.id` (which would remount it on every photo change and lose stream state). |
| `template-struct-field-blind-spot` | The People card and Comments component access struct fields via `pp.person.photo`, `pp.person.photo_status`, `comment.account`, `@selected_photo.image`, `@selected_photo.original_filename`. These are all preserved from the existing template — do not invent new field names. The new E2E test inserts a real `:photo` with `status: "processed"` and triggers the panel render to exercise the template branches. |
| `playwright-dual-responsive-layout` | The People-card empty state renders two `<span>`s in the DOM (one `lg:hidden`, one `hidden lg:inline`). The new `lightbox_panel_test.exs` runs at the default 1280px viewport, so only the desktop copy ("Click on the photo to tag people") is visible. Asserting on that exact desktop string is safe. The mobile span ("No people tagged yet.") would also be present in the DOM but not match the desktop substring. **Add a comment in the test** noting this so a future maintainer doesn't switch to a mobile viewport without also flipping the assertion. The existing `test_id("desktop-comment-list")` / `test_id("mobile-comment-list")` pattern in the comments component is preserved. |
| `stream-items-outer-assign` | Selected comment styling depends on `@selected_comment_id` — an outer assign. The existing `handle_event("select_comment", ...)` already calls `stream_insert(:comments, comment)` after updating the assign so the row re-renders. Do NOT remove that `stream_insert` while shuffling the template. |
| `phx-no-format-whitespace-pre` | Both the mobile inline span (`<span phx-no-format class="whitespace-pre-line">{comment.text}</span>`) and the desktop bubble paragraph (`<p phx-no-format class="... whitespace-pre-line">{comment.text}</p>`) carry `phx-no-format`. If you reformat the file, the formatter will reintroduce visible whitespace inside these tags. Verify after `mix format`. |
| `svg-currentcolor-visibility` | All `<.icon>` calls in this plan use explicit `text-white/40`, `text-white/50`, etc. — never inherit `currentColor` from a parent that might match the background. |
| `clean-test-output` | After the test suite passes, also run `mix test 2>&1 | grep "\[error\]"` and confirm no `[error]` lines. Noisy log output is treated as a real failure. |

---

## File Map

| File | Disposition | Responsibility after change |
|---|---|---|
| `lib/web/components/photo_gallery.ex` | Modify (lines ~204–315 inside `lightbox/1`) | Render panel base (L1), panel header row, People tonal card, Comments card wrapper, mobile Download tonal block |
| `lib/web/live/comments/photo_comments_component.ex` | Modify (entire `render/1` template) | Render Comments card contents: title row, scrollable list with new selected-state, composer (L3 tonal block, transparent textarea) |
| `test/user_flows/lightbox_panel_test.exs` | Create | E2E coverage for new card structure: panel toggles, both `test_id`s present, empty-state copy, add-comment dismisses empty state |
| `COMPONENTS.jsonl` | Modify | Append `gallery-show-lightbox-panel` decision; update `gallery-show-lightbox-desktop` to reference it |

No other files change. The `<.user_avatar>` component is already imported in `Web` and is used as-is.

## Tonal Scale Reference (apply consistently)

| Layer | Class | Used for |
|---|---|---|
| L0 | `bg-black` | Photo backdrop (unchanged) |
| L1 | `bg-white/[0.03]` | Panel base |
| L2 | `bg-white/[0.06]` | Section cards (People, Comments) |
| L3 | `bg-white/[0.10]` | Composer surface; person-row hover (`hover:bg-white/[0.06]` → kept, but composer is L3) |
| L4 | `bg-white/[0.16]` | Selected mobile comment row, action chips |

Text opacities: section labels `text-white/90`, body `text-white/85`, author name `text-white/95`, meta/timestamp `text-white/40`, **empty state `text-white/50`** (was `/30`).

---

## Task 1: E2E test for the new panel structure

**Files:**
- Create: `test/user_flows/lightbox_panel_test.exs`

- [ ] **Step 1: Write the failing E2E test**

```elixir
defmodule Web.UserFlows.LightboxPanelTest do
  @moduledoc """
  E2E tests for the lightbox side panel structure (People + Comments cards).

  ## Scenarios

  ### Panel reveals People and Comments cards
  Given a logged-in admin with a processed photo
  When they open the lightbox and toggle the info panel
  Then both the people-card and comments-card are visible
  And both show their empty-state copy

  ### Adding a comment dismisses the comments empty state
  Given the panel open with no comments
  When the user submits a new comment
  Then the empty state disappears
  And the comment appears in the list
  """
  use Web.E2ECase

  setup do
    family = insert(:family, name: "Lightbox Panel Family")
    org = Ancestry.Organizations.get_organization!(family.organization_id)
    gallery = insert(:gallery, name: "Test Gallery", family: family)

    photo =
      insert(:photo, gallery: gallery, original_filename: "test.jpg", status: "processed")
      |> ensure_photo_file()

    %{family: family, org: org, gallery: gallery, photo: photo}
  end

  test "panel reveals People and Comments cards with empty states", %{
    conn: conn,
    family: family,
    org: org,
    gallery: gallery,
    photo: photo
  } do
    conn =
      conn
      |> log_in_e2e()
      |> visit(~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")
      |> wait_liveview()
      |> click("#photos-#{photo.id}")
      |> assert_has("#lightbox")
      |> click("#toggle-panel-btn")

    conn
    |> assert_has(test_id("lightbox-people-card"))
    |> assert_has(test_id("lightbox-comments-card"))
    |> assert_has(test_id("lightbox-people-card"), text: "Click on the photo to tag people")
    |> assert_has(test_id("lightbox-comments-card"), text: "No comments yet")
  end

  test "adding a comment dismisses the empty state", %{
    conn: conn,
    family: family,
    org: org,
    gallery: gallery,
    photo: photo
  } do
    conn =
      conn
      |> log_in_e2e()
      |> visit(~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")
      |> wait_liveview()
      |> click("#photos-#{photo.id}")
      |> assert_has("#lightbox")
      |> click("#toggle-panel-btn")
      |> assert_has(test_id("lightbox-comments-card"), text: "No comments yet")

    # Submit a new comment via the composer form. The textarea has no <label>
    # element — it has only a placeholder — so PhoenixTest.fill_in/3 (which
    # takes a label) does not apply. Use Playwright.type/3 with a CSS selector
    # (matches the pattern in test/user_flows/photo_comments_test.exs).
    conn =
      conn
      |> PhoenixTest.Playwright.type("#new-comment-text", "Hello from the test")
      |> PhoenixTest.Playwright.evaluate("""
        document.querySelector('#new-comment-form').dispatchEvent(
          new Event('submit', { bubbles: true, cancelable: true })
        );
      """)

    conn
    |> assert_has(test_id("lightbox-comments-card"), text: "Hello from the test", timeout: 5_000)
    |> refute_has(test_id("lightbox-comments-card"), text: "No comments yet")
  end
end
```

- [ ] **Step 2: Run the new test to verify it fails**

Run: `mix test test/user_flows/lightbox_panel_test.exs`

Expected: both tests FAIL with `Element with selector [data-testid='lightbox-people-card'] not found`. The `test_id`s don't exist yet — that's the failure we want.

- [ ] **Step 3: Commit**

```bash
git add test/user_flows/lightbox_panel_test.exs
git commit -m "Add failing E2E test for lightbox panel tonal cards"
```

---

## Task 2: Restructure the lightbox panel chrome in `photo_gallery.ex`

This task replaces the bordered chrome and inline People section with the L1 panel base + L2 People tonal card + L2 Comments card wrapper. The `<.live_component>` for comments stays where it is, but inside a wrapper card.

**Files:**
- Modify: `lib/web/components/photo_gallery.ex` (the panel branch inside `lightbox/1`, lines ~204–315; and the module's `import` block at the top)

- [ ] **Step 1: Add `test_id/1` import**

`Web.Components.PhotoGallery` uses `use Phoenix.Component` (not `use Web, :live_component`), so it does **not** auto-import `Web.Helpers.TestHelpers`. Add the import at the top of the module so the new `{test_id(...)}` calls compile.

In `lib/web/components/photo_gallery.ex`, find the import block (currently lines 4–5):

```elixir
import Web.CoreComponents
alias Web.Comments.PhotoCommentsComponent
```

Add a second import line directly after `Web.CoreComponents`:

```elixir
import Web.CoreComponents
import Web.Helpers.TestHelpers
alias Web.Comments.PhotoCommentsComponent
```

- [ ] **Step 2: Replace the panel branch**

Replace the entire `<%= if @panel_open do %>...<% end %>` block (currently lines ~204–314) with:

```heex
<%= if @panel_open do %>
  <%!-- Info panel: full-screen overlay on mobile, side panel on desktop --%>
  <%!-- L1 panel base — no border, slightly lifted from the lightbox black backdrop --%>
  <div class={[
    "fixed inset-0 z-50 flex flex-col bg-black text-white",
    "lg:static lg:inset-auto lg:z-auto lg:w-80 lg:shrink-0"
  ]}>
    <div class="flex flex-col h-full bg-white/[0.03] p-2 gap-2">
      <%!-- Panel header — close X, no bottom border --%>
      <div class="flex items-center justify-between px-2 py-2 shrink-0">
        <h3 class="text-sm font-ds-heading font-bold text-white/90">
          {gettext("Photo info")}
        </h3>
        <button
          type="button"
          phx-click="toggle_panel"
          class="p-2 -mr-2 rounded-ds-sharp text-white/50 hover:text-white hover:bg-white/[0.08] min-w-[44px] min-h-[44px] lg:min-w-0 lg:min-h-0 lg:p-1.5 flex items-center justify-center"
          aria-label={gettext("Close info")}
        >
          <.icon name="hero-x-mark" class="size-5 lg:w-4 lg:h-4" />
        </button>
      </div>

      <%!-- People card (L2) --%>
      <div
        {test_id("lightbox-people-card")}
        class="bg-white/[0.06] rounded-ds-sharp p-2.5 flex flex-col gap-2 shrink-0 max-h-[30vh] lg:max-h-none overflow-hidden"
      >
        <div class="flex items-center gap-2 px-1">
          <h4 class="text-xs font-ds-heading font-bold text-white/90 tracking-wide uppercase">
            {gettext("People")}
          </h4>
          <span :if={@photo_people != []} class="text-[11px] text-white/50 bg-white/[0.08] px-1.5 py-0.5 rounded-full">
            {length(@photo_people)}
          </span>
        </div>

        <div id="photo-person-list" class="overflow-y-auto">
          <%= if @photo_people == [] do %>
            <div class="text-center py-5 text-white/50">
              <div class="inline-flex items-center justify-center w-8 h-8 rounded-full bg-white/[0.04] mb-2">
                <.icon name="hero-user" class="w-4 h-4 text-white/40" />
              </div>
              <p class="text-[12.5px] leading-snug">
                <span class="lg:hidden">{gettext("No people tagged yet.")}</span>
                <span class="hidden lg:inline">{gettext("Click on the photo to tag people")}</span>
              </p>
            </div>
          <% else %>
            <div class="flex flex-col">
              <%= for pp <- @photo_people do %>
                <div
                  id={"photo-person-#{pp.id}"}
                  class="group flex items-center gap-3 lg:gap-2 px-1.5 py-2 lg:py-1.5 rounded-ds-sharp hover:bg-white/[0.06] transition-colors min-h-[44px] lg:min-h-0"
                  data-person-id={pp.person_id}
                  phx-hook="PersonHighlight"
                >
                  <%= if pp.person.photo && pp.person.photo_status == "processed" do %>
                    <img
                      src={Ancestry.Uploaders.PersonPhoto.url({pp.person.photo, pp.person}, :thumbnail)}
                      class="w-7 h-7 lg:w-6 lg:h-6 rounded-full object-cover shrink-0"
                    />
                  <% else %>
                    <div class="w-7 h-7 lg:w-6 lg:h-6 rounded-full bg-white/[0.10] flex items-center justify-center shrink-0">
                      <.icon name="hero-user" class="w-4 h-4 lg:w-3.5 lg:h-3.5 text-white/40" />
                    </div>
                  <% end %>
                  <span class="text-sm text-white/85 truncate flex-1">
                    {Ancestry.People.Person.display_name(pp.person)}
                  </span>
                  <button
                    phx-click="untag_person"
                    phx-value-photo-id={pp.photo_id}
                    phx-value-person-id={pp.person_id}
                    class="p-2 lg:p-1 rounded text-white/40 hover:text-red-400 lg:opacity-0 lg:group-hover:opacity-100 transition-all shrink-0"
                    title={gettext("Remove tag")}
                  >
                    <.icon name="hero-x-mark" class="w-4 h-4 lg:w-3.5 lg:h-3.5" />
                  </button>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>

      <%!-- Comments card (L2) — wraps the live component --%>
      <div
        {test_id("lightbox-comments-card")}
        class="bg-white/[0.06] rounded-ds-sharp flex-1 min-h-0 flex flex-col overflow-hidden"
      >
        <.live_component
          module={PhotoCommentsComponent}
          id="photo-comments"
          photo_id={@selected_photo.id}
          current_scope={@current_scope}
        />
      </div>

      <%!-- Download tonal block: mobile only --%>
      <a
        href={Ancestry.Uploaders.Photo.url({@selected_photo.image, @selected_photo}, :original)}
        download={@selected_photo.original_filename}
        class="lg:hidden shrink-0 flex items-center justify-center gap-2 bg-white/[0.10] rounded-ds-sharp py-3 text-sm font-ds-body font-semibold text-white/90 hover:bg-white/[0.16] transition-colors"
      >
        <.icon name="hero-arrow-down-tray" class="size-5" /> {gettext("Download")}
      </a>
    </div>
  </div>
<% end %>
```

Key deltas from current code (for reviewer reference):
- Removed: outer `border-l border-white/10` on desktop, header row's `border-b`, all section bottom borders
- Added: `bg-white/[0.03]` panel base, two L2 tonal cards with `test_id` attributes, mobile Download tonal block
- Header text unified to "Photo info" (was "Photo Info" mobile / "People" desktop)
- People empty-state: lifted to `text-white/50`, icon-on-tonal-circle, two copy variants kept
- Untag button: explicit on mobile (was hidden), hover-revealed on desktop (existing behavior preserved)

- [ ] **Step 3: Compile to confirm no syntax errors**

Run: `mix compile --warnings-as-errors`

Expected: clean compile.

- [ ] **Step 4: Run the new lightbox panel test**

Run: `mix test test/user_flows/lightbox_panel_test.exs`

Expected: the **first** test (cards visible) PASSES. The **second** test (add comment dismisses empty state) likely still FAILS — its empty-state copy assertion (`"No comments yet"`) is rendered by the comments component, which Task 3 changes.

- [ ] **Step 5: Run the existing tag/untag and comments tests to confirm no regression**

Run: `mix test test/user_flows/link_people_in_photos_test.exs test/user_flows/photo_comments_test.exs`

Expected: PASS. The desktop empty-state copy is unchanged (`"Click on the photo to tag people"`), `#photo-person-list` ID is preserved, `[data-person-id]` attribute is preserved, `untag_person` button still has `phx-click="untag_person"`. The desktop comment-bubble surface (`bg-white/[0.10]` after the rewrite, was `bg-white/[0.06]` — both still match the bubble-class assertion in `photo_comments_test.exs`).

- [ ] **Step 6: Commit**

```bash
git add lib/web/components/photo_gallery.ex
git commit -m "Lightbox panel: tonal cards for People + Comments, drop borders"
```

---

## Task 3: Restructure the comments component template

This task overhauls the `render/1` template in `photo_comments_component.ex` to fit inside the new L2 Comments card: drops its own panel chrome, adds the section-title row, bumps empty-state contrast, swaps composer to L3 tonal block, switches selected mobile row to L4.

**Files:**
- Modify: `lib/web/live/comments/photo_comments_component.ex` (the entire `render/1` function — currently lines ~134–286)

- [ ] **Step 1: Replace `render/1`**

Replace the existing `render(assigns)` function body with:

```elixir
@impl true
def render(assigns) do
  ~H"""
  <div id="photo-comments-panel" class="flex flex-col h-full p-2.5 gap-2 text-white">
    <%!-- Section title row --%>
    <div class="flex items-center gap-2 px-1 shrink-0">
      <h4 class="text-xs font-ds-heading font-bold text-white/90 tracking-wide uppercase">
        {gettext("Comments")}
      </h4>
      <span
        :if={@stream_count_comments > 0}
        class="text-[11px] text-white/50 bg-white/[0.08] px-1.5 py-0.5 rounded-full"
      >
        {@stream_count_comments}
      </span>
    </div>

    <%!-- Scrollable comment list --%>
    <div class="flex-1 overflow-y-auto min-h-0 px-1">
      <div id="comments-list" phx-update="stream" class="flex flex-col gap-1">
        <div id="comments-empty" class="hidden only:block text-center py-8 text-white/50">
          <div class="inline-flex items-center justify-center w-8 h-8 rounded-full bg-white/[0.04] mb-2">
            <.icon name="hero-chat-bubble-left-right" class="w-4 h-4 text-white/40" />
          </div>
          <p class="text-[12.5px] leading-snug">{gettext("No comments yet. Be the first to add one.")}</p>
        </div>

        <div :for={{id, comment} <- @streams.comments} id={id} class="group relative">
          <%= if @editing_comment_id == comment.id do %>
            <.form
              for={@edit_form}
              id={"edit-comment-#{comment.id}"}
              phx-submit="save_edit"
              phx-target={@myself}
              class="space-y-2 p-1.5"
            >
              <textarea
                name="comment[text]"
                id={"edit-comment-text-#{comment.id}"}
                rows="2"
                class="w-full bg-white/[0.10] rounded-ds-sharp px-3 py-2 text-sm text-white placeholder-white/40 focus:outline-none focus:bg-white/[0.16] resize-none"
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
                  class="px-3 py-1 bg-white/[0.10] hover:bg-white/[0.16] text-white/80 text-xs font-medium rounded-md transition-colors"
                >
                  {gettext("Cancel")}
                </button>
              </div>
            </.form>
          <% else %>
            <%!-- Mobile: ultra-compact inline with tap-to-select --%>
            <div
              {test_id("mobile-comment-list")}
              class={[
                "flex gap-2 items-start py-1.5 px-1.5 rounded-ds-sharp md:hidden transition-colors",
                @selected_comment_id == comment.id && "bg-white/[0.16]"
              ]}
              phx-click="select_comment"
              phx-value-id={comment.id}
              phx-target={@myself}
            >
              <.user_avatar account={comment.account} size={:sm} class="mt-0.5" />
              <div class="flex-1 min-w-0">
                <p class="text-[13px] text-white/85 leading-snug break-words">
                  <span class="font-semibold text-white/95">
                    {display_first_name(comment.account)}
                  </span>
                  <span phx-no-format class="whitespace-pre-line">{comment.text}</span>
                  <span class="text-[10px] text-white/40">
                    {format_short_time(comment.inserted_at)}
                  </span>
                </p>
                <%= if @selected_comment_id == comment.id do %>
                  <div class="flex items-center gap-2 mt-2">
                    <.comment_actions comment={comment} current_scope={@current_scope} myself={@myself} />
                  </div>
                <% end %>
              </div>
            </div>

            <%!-- Desktop: bubble style with floating hover actions --%>
            <div {test_id("desktop-comment-list")} class="hidden md:flex gap-2 items-start py-1">
              <.user_avatar account={comment.account} size={:sm} class="mt-0.5" />
              <div class="flex-1 min-w-0">
                <div class="flex items-baseline gap-1.5">
                  <span class="text-xs font-semibold text-white/95">
                    {display_name(comment.account)}
                  </span>
                  <time class="text-[10px] text-white/40">
                    {format_relative_time(comment.inserted_at)}
                  </time>
                </div>
                <div class="bg-white/[0.10] rounded-ds-sharp px-2.5 py-1.5 inline-block max-w-full mt-0.5">
                  <p
                    phx-no-format
                    class="text-[13px] text-white/85 leading-snug break-words whitespace-pre-line"
                  >{comment.text}</p>
                </div>
              </div>
              <%!-- Floating actions at top-right of comment row, absolute to outer group --%>
              <div class="absolute top-0 right-0 flex items-center gap-0.5 opacity-0 group-hover:opacity-100 transition-opacity bg-white/[0.16] rounded-md shadow-lg px-1 py-0.5">
                <.comment_actions comment={comment} current_scope={@current_scope} myself={@myself} />
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>

    <%!-- Composer — L3 tonal block, transparent textarea inside --%>
    <div class="shrink-0">
      <.form
        for={@form}
        id="new-comment-form"
        phx-submit="save_comment"
        phx-target={@myself}
        class="bg-white/[0.10] rounded-ds-sharp px-3 py-1.5 flex items-end gap-2"
      >
        <textarea
          name="comment[text]"
          id="new-comment-text"
          phx-hook="TextareaAutogrow"
          rows="1"
          placeholder={gettext("Add a comment...")}
          class="flex-1 bg-transparent border-0 px-0 py-2 text-sm leading-5 text-white placeholder-white/40 focus:outline-none focus:ring-0 resize-none overflow-y-auto max-h-[180px]"
        >{Phoenix.HTML.Form.normalize_value("textarea", @form[:text].value)}</textarea>
        <button
          type="submit"
          class="h-8 w-8 flex items-center justify-center bg-primary hover:bg-primary/80 text-white rounded-md transition-colors shrink-0 mb-1"
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

- [ ] **Step 2: Update `comment_actions/1` to use the new tonal classes**

Replace the `comment_actions/1` private function (currently lines ~288–314) with:

```elixir
defp comment_actions(assigns) do
  ~H"""
  <%= if can_edit?(@comment, @current_scope) do %>
    <button
      phx-click="edit_comment"
      phx-value-id={@comment.id}
      phx-target={@myself}
      class="p-1.5 rounded-md text-white/60 hover:text-white bg-white/[0.10] hover:bg-white/[0.16] transition-colors"
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
      class="p-1.5 rounded-md text-white/60 hover:text-red-400 bg-white/[0.10] hover:bg-white/[0.16] transition-colors"
      title={gettext("Delete comment")}
    >
      <.icon name="hero-trash" class="w-3.5 h-3.5" />
    </button>
  <% end %>
  """
end
```

- [ ] **Step 3: Add a `stream_count_comments` assign so the count chip works**

The count chip references `@stream_count_comments`. Streams don't expose a length directly. Wire it in the component's `update/2` and `handle_event/3` callbacks.

In `update(assigns, socket)` (currently lines ~20–34), replace the body with:

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
   |> assign(:selected_comment_id, nil)
   |> assign(:edit_form, nil)
   |> assign(:form, to_form(changeset, as: :comment))
   |> assign(:stream_count_comments, length(comments))
   |> stream(:comments, comments, reset: true)}
end
```

Update the three message-receiving `update/2` clauses at the top of the module to keep the count in sync:

```elixir
def update(%{comment_created: comment}, socket) do
  {:ok,
   socket
   |> update(:stream_count_comments, &(&1 + 1))
   |> stream_insert(:comments, comment)}
end

def update(%{comment_updated: comment}, socket) do
  {:ok, stream_insert(socket, :comments, comment)}
end

def update(%{comment_deleted: comment}, socket) do
  {:ok,
   socket
   |> update(:stream_count_comments, &max(&1 - 1, 0))
   |> stream_delete(:comments, comment)}
end
```

**Leave `save_comment` unchanged.** The broadcast does reach the originating tab: `Ancestry.Comments.create_photo_comment/3` broadcasts `{:comment_created, comment}` on `photo_comments:#{photo_id}` (`lib/ancestry/comments.ex:16`); `Web.PhotoInteractions` subscribes to that topic for the currently selected photo (`lib/web/photo_interactions.ex:62`); `Web.GalleryLive.Show.handle_info({:comment_created, _}, ...)` (`lib/web/live/gallery_live/show.ex:208`) routes through `Web.PhotoInteractions.handle_comment_info/2` (`lib/web/photo_interactions.ex:148`), which calls `send_update(PhotoCommentsComponent, id: "photo-comments", comment_created: comment)`. That `send_update` runs on every subscribing LiveView including the originating tab, so the per-message `update/2` clauses above keep the count in sync without an optimistic insert.

- [ ] **Step 4: Compile**

Run: `mix compile --warnings-as-errors`

Expected: clean.

- [ ] **Step 5: Run all lightbox- and comment-related tests**

Run: `mix test test/user_flows/lightbox_panel_test.exs test/user_flows/photo_comments_mobile_test.exs test/user_flows/link_people_in_photos_test.exs test/user_flows/gallery_back_button_after_lightbox_test.exs`

Expected: all PASS. The mobile-comments selection test uses `test_id("mobile-comment-list")` (preserved) and asserts on the `phx-click='edit_comment'` and `delete_comment` buttons (preserved). The link-people test uses `#photo-person-list` (preserved) and "Click on the photo to tag people" (preserved on desktop).

- [ ] **Step 6: Commit**

```bash
git add lib/web/live/comments/photo_comments_component.ex
git commit -m "Comments component: drop borders, L3 composer, L4 selected row"
```

---

## Task 4: Update COMPONENTS.jsonl

**Files:**
- Modify: `COMPONENTS.jsonl`

- [ ] **Step 1: Append the new component decision and update the existing one**

Find the existing `gallery-show-lightbox-desktop` line (line 9). Update it to:

```json
{"component": "gallery-show-lightbox-desktop", "description": "Current layout preserved: side panel for people/comments (see gallery-show-lightbox-panel for the panel's tonal system), thumbnail strip at bottom, arrow key navigation. Photo tagging enabled on desktop only."}
```

Append a new line at the end of the file:

```json
{"component": "gallery-show-lightbox-panel", "description": "Dark-mode tonal panel with 4-step scale (L1 0.03, L2 0.06, L3 0.10, L4 0.16 on white). People + Comments rendered as L2 cards on L1 base. No border dividers — section separation via card edges and whitespace. Empty states at text-white/50. Composer is an L3 tonal block with a borderless textarea inside. Selected mobile comment uses L4 instead of an outline. Header label unified to 'Photo info' across breakpoints."}
```

- [ ] **Step 2: Verify the file is still valid JSONL (one object per line, no trailing comma)**

Run: `head -5 COMPONENTS.jsonl && tail -3 COMPONENTS.jsonl`

Expected: each line is a complete JSON object, no syntax errors.

- [ ] **Step 3: Commit**

```bash
git add COMPONENTS.jsonl
git commit -m "Document gallery-show-lightbox-panel component decision"
```

---

## Task 5: Final verification

- [ ] **Step 1: Run `mix precommit`**

Run: `mix precommit`

Expected: compile clean (warnings-as-errors), unused deps removed, format applied, full test suite passes.

- [ ] **Step 1a: Verify clean test output (no log errors)**

Per the `clean-test-output` learning, the precommit's "all green" status doesn't catch noisy logs. Run:

```bash
mix test 2>&1 | grep "\[error\]"
```

Expected: no output. If any `[error]` lines appear (especially around photo file paths or Waffle storage), the factory is creating DB records without on-disk files — fix the factory call to use `ensure_photo_file/1` from `Web.E2ECase`. (Warnings are advisory: scan but don't treat as blocking unless they look related to this change.)

If formatting changes any of the touched files, create a follow-up commit (do not amend — amending after a hook runs is needlessly destructive of message history):

```bash
git add -u lib/ test/
git commit -m "Apply mix format"
```

- [ ] **Step 2: Manual smoke test in the browser**

Run: `iex -S mix phx.server` in one terminal. In a second terminal or browser:

1. Visit a gallery, click a photo, click the info-circle icon.
2. Confirm the panel renders with two visibly tonal cards on a slightly lifted base.
3. Confirm empty states are readable (not the `text-white/30` ghost they used to be).
4. Tag a person, confirm the row appears with avatar.
5. Type a comment, send it, confirm it appears and the empty state disappears.
6. On a narrow viewport (~414px) confirm the panel goes full-screen, the Download tonal block appears at the bottom, and tapping a comment reveals the inline Edit/Delete chips.
7. Close the panel — the lightbox photo view returns intact.

Note any visual surprises (especially the panel header without a border — the spec calls this out as a "live with it before judging" change).

---

## Out of Scope (deferred)

- Lightbox top bar redesign
- Thumbnail strip redesign
- People-tagging dropdown redesign (same border-heavy problem; documented for follow-up)
- Adding a desktop selection model (`select_comment`) for parity with mobile
- Promoting the dark tonal scale into reusable `bg-ds-dark-surface-*` tokens — only a single component uses them right now; revisit if a second surface adopts the pattern
