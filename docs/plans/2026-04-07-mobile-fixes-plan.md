# Mobile fixes punch list — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship seven independent UX fixes plus a corrective file-cleanup refactor for family/organization deletion, in a single bundled PR.

**Architecture:** Each issue is independent. Tasks are ordered by risk: pure edits first, JS changes next, state plumbing in the middle, data-touching changes last. The biggest task — Issue 7 — has its prerequisite (file cleanup refactor in `Ancestry.Families` / `Ancestry.Organizations`) split into its own subtask so the LiveView changes can build on a known-correct context layer.

**Tech Stack:** Phoenix LiveView, Ecto, Tailwind CSS v4, ExMachina factories, `Web.E2ECase` for end-to-end user flow tests.

**Spec:** `docs/plans/2026-04-07-mobile-fixes-design.md`

**Pre-flight notes:**
- Project uses `mix precommit` (compile w/ warnings-as-errors, format, tests). Run after each task before final commit.
- Tests follow patterns in `test/CLAUDE.md` and `test/user_flows/CLAUDE.md`. New flow tests model on `test/user_flows/delete_family_test.exs`.
- Web layer namespace is `Web` (not `AncestryWeb`).
- DB cascade FKs verified: `organizations → families → galleries → photos`, `families → family_members → persons`. All are `ON DELETE CASCADE` at the Postgres level.
- Use the project's existing `test_id` helper (`Web.TestHelpers`) for selectors in tests where available; mirror neighboring tests if not.
- Reference existing learnings inline where they apply: `mobile-toolbar-pattern`, `drawer-action-close-drawer`, `audit-generated-auth-defaults`, `pure-presentation-components`, `update-dependent-assigns`, `js-hook-native-types`, `stable-livecomponent-ids`, `router-on-mount-hooks`.

---

## Task 1: Issue 6 — Delete sudo-mode `on_mount` from settings

Smallest possible change: a one-line deletion. Do this first to warm up and confirm the test pipeline works.

**Files:**
- Modify: `lib/web/live/account_live/settings.ex:4`

- [ ] **Step 1: Read current state**

```bash
sed -n '1,10p' lib/web/live/account_live/settings.ex
```

Confirm line 4 reads `on_mount {Web.AccountAuth, :require_sudo_mode}`.

- [ ] **Step 2: Check the router-level live_session is in place**

```bash
sed -n '83,95p' lib/web/router.ex
```

Confirm `live_session :require_authenticated_account` lists `on_mount: [{Web.AccountAuth, :require_authenticated}]` and includes `live "/accounts/settings", AccountLive.Settings, :edit`.

- [ ] **Step 3: Write the failing test**

Add a new test case in `test/web/live/account_live/settings_test.exs` (or create the file if it doesn't exist — model on whichever existing settings test the project ships, or the example below):

```elixir
defmodule Web.AccountLive.SettingsTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Ancestry.Factory  # ex_machina

  test "logged-in account beyond the sudo window can load settings without re-auth", %{conn: conn} do
    account = insert(:account)

    # Build a session token that was issued more than 10 minutes ago
    # so :require_sudo_mode would have rejected it.
    stale_token =
      Ancestry.Identity.generate_account_session_token(account)
      |> tap(fn _ ->
        # Force the inserted_at backwards via raw SQL so the token looks old.
        Ancestry.Repo.query!(
          "UPDATE accounts_tokens SET inserted_at = NOW() - INTERVAL '20 minutes' WHERE account_id = $1",
          [account.id]
        )
      end)

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:account_token, stale_token)

    {:ok, _view, html} = live(conn, ~p"/accounts/settings")
    assert html =~ "Account Settings"
  end
end
```

If the project already ships a `settings_test.exs`, append the test case there instead and adjust the imports.

- [ ] **Step 4: Run the test to verify it fails**

```bash
mix test test/web/live/account_live/settings_test.exs
```

Expected: FAIL with redirect to `/accounts/log-in` (because `:require_sudo_mode` rejects the stale token).

- [ ] **Step 5: Apply the one-line fix**

In `lib/web/live/account_live/settings.ex`, **delete** line 4 (`on_mount {Web.AccountAuth, :require_sudo_mode}`) entirely. The line is removed, not replaced — the router-level live_session already provides `:require_authenticated`.

- [ ] **Step 6: Run the test to verify it passes**

```bash
mix test test/web/live/account_live/settings_test.exs
```

Expected: PASS.

- [ ] **Step 7: Run any existing settings tests to verify no regression**

```bash
mix test test/web/live/account_live/
```

Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/web/live/account_live/settings.ex test/web/live/account_live/settings_test.exs
git commit -m "Remove sudo mode from settings page

The router-level live_session :require_authenticated_account already
enforces :require_authenticated. The module-level on_mount that added
:require_sudo_mode forced re-login on every visit, which is overkill
for this app's threat model.

See docs/learnings.jsonl#audit-generated-auth-defaults and
docs/learnings.jsonl#router-on-mount-hooks."
```

---

## Task 2: Issue 1 — `FamilyLive.Index` toolbar follows mobile pattern

Pure layout reshuffle. No new behavior; the People + New Family actions still work, they just move from always-visible to desktop-only-plus-drawer-mobile.

**Files:**
- Modify: `lib/web/live/family_live/index.html.heex` (toolbar at lines 2-35, nav drawer at lines 37-46)

- [ ] **Step 1: Read the canonical pattern**

Open `lib/web/live/family_live/show.html.heex:1-40` and `lib/web/live/gallery_live/show.html.heex:75-98` for reference. Confirm the structure: `py-2`, action group wrapped in `hidden lg:flex`, drawer `:page_actions` slot containing `<.nav_action>` entries.

- [ ] **Step 2: Restructure the toolbar**

In `lib/web/live/family_live/index.html.heex`, replace lines 2-35 with the canonical pattern. The new toolbar:

```heex
<:toolbar>
  <div class="flex items-center justify-between px-4 py-2 bg-ds-surface-low sm:px-6 lg:px-8">
    <div class="flex items-center gap-2 min-w-0">
      <button
        type="button"
        phx-click={toggle_nav_drawer()}
        class="p-2 -ml-2 text-ds-on-surface-variant hover:text-ds-on-surface lg:hidden min-w-[44px] min-h-[44px] flex items-center justify-center"
        aria-label="Open menu"
      >
        <.icon name="hero-bars-3" class="size-5" />
      </button>
      <h1 class="text-lg font-ds-heading font-bold text-ds-on-surface">
        Families
      </h1>
    </div>
    <div class="hidden lg:flex items-center gap-2">
      <.link
        navigate={~p"/org/#{@current_scope.organization.id}/people"}
        class="inline-flex items-center gap-2 bg-ds-surface-high text-ds-on-surface rounded-ds-sharp px-4 py-2.5 text-sm font-ds-body font-semibold hover:bg-ds-surface-highest transition-colors"
        {test_id("org-people-btn")}
      >
        <.icon name="hero-users" class="w-4 h-4" /> People
      </.link>
      <.link
        id="new-family-btn"
        navigate={~p"/org/#{@current_scope.organization.id}/families/new"}
        class="inline-flex items-center gap-2 bg-gradient-to-b from-ds-primary to-ds-primary-container text-ds-on-primary rounded-ds-sharp px-5 py-2.5 text-sm font-ds-body font-semibold tracking-wide hover:opacity-90 transition-opacity"
        {test_id("family-new-btn")}
      >
        New Family
      </.link>
    </div>
  </div>
</:toolbar>
```

- [ ] **Step 3: Add `:page_actions` slot to the nav drawer**

Locate the `<.nav_drawer>` block (currently lines 37-46) and add a `:page_actions` slot before its other children:

```heex
<.nav_drawer current_scope={@current_scope}>
  <:page_actions>
    <.nav_action
      icon="hero-users"
      label="People"
      phx-click={
        toggle_nav_drawer()
        |> JS.navigate(~p"/org/#{@current_scope.organization.id}/people")
      }
    />
    <.nav_action
      icon="hero-plus"
      label="New family"
      phx-click={
        toggle_nav_drawer()
        |> JS.navigate(~p"/org/#{@current_scope.organization.id}/families/new")
      }
    />
  </:page_actions>
  <.link
    href={~p"/org"}
    class="flex items-center gap-3 w-full px-2 py-3 text-left rounded-ds-sharp min-h-[44px] text-ds-on-surface hover:bg-ds-surface-high transition-colors"
  >
    <.icon name="hero-building-office-2" class="size-5 shrink-0 text-ds-on-surface-variant" />
    <span class="font-ds-body text-sm">Organizations</span>
  </.link>
</.nav_drawer>
```

(Reference for the chained `JS.navigate` pattern: `family_live/show.html.heex:135-143`.)

- [ ] **Step 4: Run existing family-index tests to confirm no regression**

```bash
mix test test/user_flows/create_family_test.exs test/user_flows/delete_family_test.exs
```

Expected: all PASS. If a test fails because it asserts on the toolbar markup positions, update the test to use the new selectors.

- [ ] **Step 5: Visually verify mobile + desktop**

In a dev session: `iex -S mix phx.server`. Open `/org/<org_id>` on a narrow viewport (DevTools mobile mode) and confirm:
- The toolbar shows hamburger + "Families" only on mobile.
- The People + New Family actions appear inside the nav drawer.
- On desktop (≥1024px) the People + New Family buttons appear in the toolbar as before.

- [ ] **Step 6: Run `mix precommit`**

```bash
mix precommit
```

Expected: clean.

- [ ] **Step 7: Commit**

```bash
git add lib/web/live/family_live/index.html.heex
git commit -m "Apply mobile toolbar pattern to family index

Tighten padding to py-2, drop the max-w-7xl wrapper, hide the People
and New Family actions on mobile (hidden lg:flex), and expose them
through the nav drawer's :page_actions slot.

Mobile users hit overflow with multi-word labels like New Family
wrapping to two lines on the previous toolbar.

See docs/learnings.jsonl#mobile-toolbar-pattern."
```

---

## Task 3: Issue 2 — Gallery FAB hidden when lightbox open + guard `PhotoTagger.destroyed()`

Two tiny additive fixes that together resolve the mobile FAB-broken-after-lightbox-close bug.

**Files:**
- Modify: `lib/web/live/gallery_live/show.html.heex:101-107` (FAB block)
- Modify: `assets/js/photo_tagger.js:267-275` (`destroyed` callback)
- Test: `test/user_flows/gallery_back_button_after_lightbox_test.exs` (new file)

- [ ] **Step 1: Write the failing user-flow test**

Create `test/user_flows/gallery_back_button_after_lightbox_test.exs`:

```elixir
defmodule Web.UserFlows.GalleryBackButtonAfterLightboxTest do
  use Web.E2ECase

  setup do
    family = insert(:family, name: "Test Family")
    org = Ancestry.Organizations.get_organization!(family.organization_id)
    gallery = insert(:gallery, family: family, name: "Photos")
    photo = insert(:photo, gallery: gallery, status: "processed")
    %{org: org, family: family, gallery: gallery, photo: photo}
  end

  # Given a gallery with at least one processed photo
  # When the user opens the gallery on mobile
  # And taps a photo to maximize it
  # Then the floating back button is hidden while the lightbox is open
  #
  # When the user closes the lightbox
  # Then the floating back button is visible again
  # And tapping it navigates back to the family page
  test "back FAB is hidden during lightbox and works after close", %{
    conn: conn,
    org: org,
    family: family,
    gallery: gallery,
    photo: photo
  } do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}/galleries/#{gallery.id}")
      |> wait_liveview()

    # FAB visible before opening any photo
    conn |> assert_has("a[aria-label='Back to family']")

    # Open the photo (lightbox)
    conn =
      conn
      |> click("#photos-#{photo.id}")
      |> wait_liveview()

    # FAB is NOT in the DOM while the lightbox is open
    conn |> refute_has("a[aria-label='Back to family']")

    # Close the lightbox via the X button
    conn =
      conn
      |> click("#lightbox button[aria-label='Close']")
      |> wait_liveview()

    # FAB is back, and clicking it navigates to the family show page
    conn
    |> assert_has("a[aria-label='Back to family']")
    |> click("a[aria-label='Back to family']")
    |> wait_liveview()
    |> assert_has(test_id("family-name"), text: "Test Family")
  end
end
```

If `refute_has`, `assert_has`, or `click` selector forms differ in this project's `Web.E2ECase`, adjust to match the existing tests in `test/user_flows/`.

- [ ] **Step 2: Run the test to verify it fails**

```bash
mix test test/user_flows/gallery_back_button_after_lightbox_test.exs
```

Expected: FAIL — the FAB is currently rendered regardless of `@selected_photo`, so `refute_has` will fail at the lightbox-open assertion.

- [ ] **Step 3: Hide the FAB while lightbox is open**

In `lib/web/live/gallery_live/show.html.heex`, locate the FAB block (currently around lines 100-107). Wrap it in a conditional or add `:if`:

```heex
<%!-- Floating back FAB: mobile only, hidden while lightbox is open --%>
<.link
  :if={is_nil(@selected_photo)}
  navigate={~p"/org/#{@current_scope.organization.id}/families/#{@family.id}"}
  class="fixed bottom-4 left-4 z-30 bg-ds-surface-card shadow-ds-ambient rounded-full min-w-[44px] min-h-[44px] flex items-center justify-center pb-[env(safe-area-inset-bottom)] lg:hidden"
  aria-label="Back to family"
>
  <.icon name="hero-arrow-left" class="size-5 text-ds-on-surface" />
</.link>
```

The only change is the `:if={is_nil(@selected_photo)}` attribute.

- [ ] **Step 4: Guard `PhotoTagger.destroyed()` against undefined containers**

In `assets/js/photo_tagger.js`, locate the `destroyed()` callback (currently lines 267-275). Add an early-return guard at the top:

```js
destroyed() {
  // mounted() short-circuits on mobile (window.innerWidth < 1024) and
  // never assigns these fields. Without this guard the unmount throws
  // a TypeError on every lightbox close on mobile, corrupting LiveView's
  // hook teardown lifecycle.
  if (!this.circlesContainer) return

  if (this._raf) cancelAnimationFrame(this._raf)
  window.removeEventListener("resize", this._onResize)
  if (this._clickAway) {
    document.removeEventListener("click", this._clickAway)
  }
  this.circlesContainer.remove()
  this.popoverContainer.remove()
}
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
mix test test/user_flows/gallery_back_button_after_lightbox_test.exs
```

Expected: PASS.

- [ ] **Step 6: Manual verification on a real mobile viewport**

In `iex -S mix phx.server`, open the gallery with DevTools in mobile mode (≤1023 px wide):
1. Confirm the FAB is visible.
2. Tap a photo. Confirm the lightbox opens AND the FAB disappears.
3. Tap the X. Confirm the lightbox closes AND the FAB reappears.
4. Open the JS console and confirm there is no `TypeError` on lightbox close.
5. Tap the FAB. Confirm navigation to the family page works.

- [ ] **Step 7: Run gallery tests to verify no regression**

```bash
mix test test/user_flows/link_people_in_photos_test.exs test/web/live/gallery_live/
```

Expected: all PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/web/live/gallery_live/show.html.heex assets/js/photo_tagger.js test/user_flows/gallery_back_button_after_lightbox_test.exs
git commit -m "Fix gallery back FAB unresponsive after lightbox close on mobile

Two changes:

1. Hide the FAB while the lightbox is open. The lightbox has its own
   X close button; the FAB has nothing to do while a photo is
   maximized and was visually overlapping it.

2. Guard PhotoTagger.destroyed() against undefined containers.
   PhotoTagger.mounted() short-circuits on mobile (innerWidth < 1024)
   and never creates the overlay containers. The unguarded destroyed()
   then threw a TypeError on every lightbox close on mobile, leaving
   LiveView's hook teardown in a bad state and freezing further click
   handling on the page."
```

---

## Task 4: Issue 5 — Compact, height-limited search results in Add Relationship modal

Pre-Issue 4 because it's a pure markup change inside the same component, and shipping it first means Task 5 (the `:choose` step) can verify the compact rows render correctly when the search step is reached through the new entry path.

**Files:**
- Modify: `lib/web/live/shared/add_relationship_component.ex` (search results block, around lines 228-241)

- [ ] **Step 1: Read the current search-results markup**

```bash
sed -n '195,260p' lib/web/live/shared/add_relationship_component.ex
```

Locate the `<%= if @search_results != [] do %>` block. Note the current row is rendered via `<.person_card_inline person={result} highlighted={false} />` inside a `<button>`.

- [ ] **Step 2: Replace with compact row markup**

Change the `<%= if @search_results != [] do %>` block to render compact rows directly. The new container is `max-h-44` (≈4 rows × ~2.25rem each):

```heex
<%= if @search_results != [] do %>
  <div class="space-y-0.5 max-h-44 overflow-y-auto" id="add-relationship-search-results">
    <%= for result <- @search_results do %>
      <button
        id={"search-result-#{result.id}"}
        type="button"
        phx-click="select_person"
        phx-target={@myself}
        phx-value-id={result.id}
        class="w-full flex items-center gap-2 px-2 py-1.5 rounded-ds-sharp hover:bg-ds-surface-highest transition-colors text-left"
      >
        <div class="w-6 h-6 rounded-full bg-ds-primary/10 flex items-center justify-center overflow-hidden flex-shrink-0">
          <%= if result.photo && result.photo_status == "processed" do %>
            <img
              src={Ancestry.Uploaders.PersonPhoto.url({result.photo, result}, :thumbnail)}
              alt={Ancestry.People.Person.display_name(result)}
              class="w-full h-full object-cover"
            />
          <% else %>
            <.icon name="hero-user" class="w-3 h-3 text-ds-primary" />
          <% end %>
        </div>
        <span class="text-sm text-ds-on-surface truncate">
          {Ancestry.People.Person.display_name(result)}
        </span>
      </button>
    <% end %>
  </div>
<% else %>
  <%= if String.length(@search_query) >= 2 do %>
    <p class="text-sm text-ds-on-surface-variant text-center py-4">
      No results found
    </p>
  <% end %>
<% end %>
```

The `:metadata` step still uses `person_card_inline` for the confirmation card; do not change that.

- [ ] **Step 3: Run any existing add-relationship tests**

```bash
mix test test/user_flows/link_person_test.exs
```

Expected: PASS. (The select_person event and id contract is unchanged, only the row markup.)

- [ ] **Step 4: Visually verify**

In `iex -S mix phx.server`, navigate to a family tree, click a parent placeholder card, type 2+ characters in the search input. Confirm:
- Each row is shorter than the previous (~2.25rem).
- Exactly 4 rows are visible before the container scrolls.

- [ ] **Step 5: `mix precommit`**

```bash
mix precommit
```

- [ ] **Step 6: Commit**

```bash
git add lib/web/live/shared/add_relationship_component.ex
git commit -m "Compact search results in Add Relationship modal

Inline a denser row markup with a 6x6 avatar and a single-line name.
Container max-h-44 shows ~4 rows before scroll, instead of the prior
~3 rows of full person_card_inline."
```

---

## Task 5: Issue 3 — Close mobile nav drawer when a person is focused (with `SidePanelComponent` passthrough)

Threads a new flag through `SidePanelComponent` → `PeopleListComponent` so the drawer instance dispatches a chained `JS` command and the desktop instance keeps the plain `phx-click`.

**Files:**
- Modify: `lib/web/live/family_live/people_list_component.ex`
- Modify: `lib/web/live/family_live/side_panel_component.ex`
- Modify: `lib/web/live/family_live/show.html.heex` (drawer + desktop side panel mounts)
- Test: `test/user_flows/tree_drawer_closes_on_focus_test.exs` (new file)

- [ ] **Step 1: Verify the `focus_person` handler signature**

```bash
sed -n '100,120p' lib/web/live/family_live/show.ex
```

Note the parameter shape (string or integer id). If it does `String.to_integer(id)`, plan to pass a stringified id from the JS.push. **This is the `js-hook-native-types` pitfall — verify before writing the markup.**

- [ ] **Step 2: Write the failing user-flow test**

Create `test/user_flows/tree_drawer_closes_on_focus_test.exs`:

```elixir
defmodule Web.UserFlows.TreeDrawerClosesOnFocusTest do
  use Web.E2ECase

  setup do
    family = insert(:family, name: "Tree Test Family")
    org = Ancestry.Organizations.get_organization!(family.organization_id)
    person = insert(:person, given_name: "Alice", surname: "Tester")
    Ancestry.People.add_to_family(person, family)
    %{org: org, family: family, person: person}
  end

  # Given a family with at least one person
  # When the user opens the family tree on mobile
  # And opens the nav drawer
  # And taps a person in the people list inside the drawer
  # Then the drawer closes
  # And the focused person is highlighted in the tree behind it
  test "drawer closes when focusing a person from inside the drawer", %{
    conn: conn,
    org: org,
    family: family,
    person: person
  } do
    conn = log_in_e2e(conn)

    conn =
      conn
      |> visit(~p"/org/#{org.id}/families/#{family.id}")
      |> wait_liveview()

    # Open the drawer
    conn =
      conn
      |> click("button[aria-label='Open menu']")
      |> wait_liveview()
      |> assert_has("#nav-drawer.open")  # selector may differ; adjust to project's drawer markup

    # Tap the person inside the drawer's people list
    conn =
      conn
      |> click(test_id("person-item-#{person.id}") <> " button")
      |> wait_liveview()

    # The drawer should be closed
    conn |> refute_has("#nav-drawer.open")

    # The focused person should be visible in the tree
    conn |> assert_has(".tree-canvas", text: "Alice")
  end
end
```

The exact drawer-open selector depends on the existing nav drawer implementation; mirror what other drawer-related assertions already use in the project's tests, or read `lib/web/components/nav_drawer.ex` to find the open-state class/attribute. If the drawer uses `data-state` or similar, adapt accordingly.

- [ ] **Step 3: Run the test to verify it fails**

```bash
mix test test/user_flows/tree_drawer_closes_on_focus_test.exs
```

Expected: FAIL — the drawer stays open after tapping a person.

- [ ] **Step 4: Add the `close_drawer_on_select` attr to `PeopleListComponent`**

In `lib/web/live/family_live/people_list_component.ex`, at the top of the module add:

```elixir
alias Phoenix.LiveView.JS
import Web.Components.NavDrawer, only: [toggle_nav_drawer: 0]
```

(Verify `Web.Components.NavDrawer` is the correct module that exports `toggle_nav_drawer/0` — read `lib/web/components/nav_drawer.ex` to confirm. Adjust the import path if it's a different module.)

Add a new attr declaration if `attr/3` is used elsewhere in the file, or use `assign_new` in `update/2`. The simplest path: declare via `attr` at the top of `render/1` (it's a `live_component` so `attr` macros work):

```elixir
attr :id, :string, required: true
attr :people, :list, required: true
attr :family_id, :integer, required: true
attr :organization, :map, required: true
attr :focus_person_id, :integer, default: nil
attr :close_drawer_on_select, :boolean, default: false
```

(If the existing component does not declare attrs, just read `assigns.close_drawer_on_select` with a `Map.get(assigns, :close_drawer_on_select, false)` call inside `render/1`.)

- [ ] **Step 5: Conditionally render the row button's click handler**

In the row markup (currently `people_list_component.ex:70-93`), replace the static `phx-click="focus_person"` with a conditional. Define a small helper at the bottom of the module:

```elixir
defp focus_click(%{close_drawer_on_select: true}, person_id) do
  toggle_nav_drawer() |> JS.push("focus_person", value: %{id: to_string(person_id)})
end

defp focus_click(_assigns, person_id) do
  JS.push("focus_person", value: %{id: to_string(person_id)})
end
```

Then in the row markup:

```heex
<button
  phx-click={focus_click(assigns, person.id)}
  class="flex items-center gap-2 flex-1 min-w-0 cursor-pointer"
>
```

(Note: passing `to_string(person.id)` as the value keeps the `focus_person` handler's existing string-id contract intact, sidestepping the `js-hook-native-types` pitfall — this is the safer default.)

- [ ] **Step 6: Pass `close_drawer_on_select` through `SidePanelComponent`**

In `lib/web/live/family_live/side_panel_component.ex`:

1. Add the attr declaration (or `Map.get`) for `close_drawer_on_select` (default `false`).
2. In the `<.live_component module={PeopleListComponent} ...>` mount (currently around lines 93-100), pass `close_drawer_on_select={@close_drawer_on_select}`.

- [ ] **Step 7: Set the flag on the drawer instance only**

In `lib/web/live/family_live/show.html.heex`:

1. Inside the `<:page_panel>` slot of the nav drawer (around lines 152-163), pass `close_drawer_on_select={true}` to `<.live_component module={Web.FamilyLive.SidePanelComponent} ...>`.
2. In the desktop side panel mount (around lines 252-264), do **not** pass the attr (or pass `false`). It defaults to `false`.

- [ ] **Step 8: Run the failing test to verify it passes**

```bash
mix test test/user_flows/tree_drawer_closes_on_focus_test.exs
```

Expected: PASS.

- [ ] **Step 9: Verify desktop behavior is unchanged**

Run any existing family-show tests to confirm desktop person-focus still works:

```bash
mix test test/user_flows/manage_people_test.exs test/user_flows/family_metrics_test.exs
```

Expected: PASS.

- [ ] **Step 10: Manual verification on mobile**

Open the family tree on a narrow viewport, open the drawer, tap a person, confirm drawer closes and the person is focused in the tree. Open the drawer again — the people list should still be filterable.

- [ ] **Step 11: `mix precommit`**

```bash
mix precommit
```

- [ ] **Step 12: Commit**

```bash
git add lib/web/live/family_live/people_list_component.ex \
        lib/web/live/family_live/side_panel_component.ex \
        lib/web/live/family_live/show.html.heex \
        test/user_flows/tree_drawer_closes_on_focus_test.exs
git commit -m "Close mobile nav drawer when focusing a person

The people list inside the drawer dispatches focus_person but never
closed the drawer, leaving the just-focused person hidden behind it.

Pass close_drawer_on_select through SidePanelComponent down to
PeopleListComponent. The drawer instance opts in; the desktop side
panel keeps the plain phx-click. JS.push value is stringified to keep
the focus_person handler's existing string-id contract intact.

See docs/learnings.jsonl#drawer-action-close-drawer
and docs/learnings.jsonl#js-hook-native-types."
```

---

## Task 6: Issue 4 — Add Relationship `:choose` entry step

A new initial step that splits "Link existing person" and "Create new person" into two equally-weighted top-level options.

**Files:**
- Modify: `lib/web/live/shared/add_relationship_component.ex`
- Test: `test/user_flows/link_person_test.exs` (extend) or `test/user_flows/add_relationship_choose_step_test.exs` (new — pick whichever makes more sense for cohesion)

- [ ] **Step 1: Decide test placement**

Read `test/user_flows/link_person_test.exs`. If the existing flow test is short enough (well under the 1000-line cap) and clearly covers the same modal, extend it with new test cases for the `:choose` step. Otherwise create a new file `test/user_flows/add_relationship_choose_step_test.exs`. The decision rule from `test/user_flows/CLAUDE.md`: "based on how related the flows are."

- [ ] **Step 2: Write the failing tests**

Add (or create) Given/When/Then tests for the new flow:

```elixir
# Given a family with at least one person
# When the user opens the Add Parent modal from a tree placeholder
# Then a Choose step is shown with two options: Link existing / Create new

# When the user clicks Link existing
# Then the search step is shown

# When the user clicks Back
# Then the Choose step is shown again (with no stale search query)

# When the user clicks Create new from the Choose step
# Then the quick-create form is shown with empty fields
```

Use the existing `link_person_test.exs` as a structural model. Selectors should be stable test_id-style; add `id` attributes to the new buttons in the next step so the tests can target them.

- [ ] **Step 3: Run tests to verify they fail**

```bash
mix test test/user_flows/link_person_test.exs   # or the new file
```

Expected: FAIL — the `:choose` step doesn't exist yet.

- [ ] **Step 4: Add the `:choose` step to the component**

In `lib/web/live/shared/add_relationship_component.ex`:

1. **Update `update/2`** — change the initial step from `:search` to `:choose`:

   ```elixir
   |> assign_new(:step, fn -> :choose end)
   ```

2. **Add a new event handler `back_to_choose`** that resets transient state:

   ```elixir
   def handle_event("back_to_choose", _, socket) do
     {:noreply,
      socket
      |> assign(:step, :choose)
      |> assign(:search_query, "")
      |> assign(:search_results, [])
      |> assign(:selected_person, nil)
      |> assign(:person_form, to_form(People.change_person(%Person{}), as: :person))}
   end
   ```

3. **Add a `start_search` event handler** (mirrors `start_quick_create`):

   ```elixir
   def handle_event("start_search", _, socket) do
     {:noreply,
      socket
      |> assign(:step, :search)
      |> assign(:search_query, "")
      |> assign(:search_results, [])}
   end
   ```

4. **Add the `<% :choose -> %>` branch** in the `case @step` block at the top of the render:

   ```heex
   <% :choose -> %>
     <div class="space-y-3">
       <p class="text-sm text-ds-on-surface-variant">
         Add a relationship by linking an existing person or creating a new one.
       </p>
       <button
         id="add-rel-link-existing-btn"
         type="button"
         phx-click="start_search"
         phx-target={@myself}
         class="w-full flex items-center gap-3 p-4 rounded-ds-sharp bg-ds-surface-low hover:bg-ds-surface-highest transition-colors text-left"
       >
         <.icon name="hero-magnifying-glass" class="w-5 h-5 text-ds-primary shrink-0" />
         <div class="flex-1 min-w-0">
           <p class="text-sm font-ds-body font-semibold text-ds-on-surface">
             Link existing person
           </p>
           <p class="text-xs text-ds-on-surface-variant">
             Search for someone already in this organization.
           </p>
         </div>
       </button>
       <button
         id="add-rel-create-new-btn"
         type="button"
         phx-click="start_quick_create"
         phx-target={@myself}
         class="w-full flex items-center gap-3 p-4 rounded-ds-sharp bg-ds-surface-low hover:bg-ds-surface-highest transition-colors text-left"
       >
         <.icon name="hero-plus" class="w-5 h-5 text-ds-primary shrink-0" />
         <div class="flex-1 min-w-0">
           <p class="text-sm font-ds-body font-semibold text-ds-on-surface">
             Create new person
           </p>
           <p class="text-xs text-ds-on-surface-variant">
             Add someone who isn't in the system yet.
           </p>
         </div>
       </button>
     </div>
   ```

- [ ] **Step 5: Replace the "Person not listed?" tertiary link in the `:search` step**

Inside the existing `<% :search -> %>` block, **remove** the `<button id="start-quick-create-btn">` block at the bottom. Add a "Back" button at the top of the search step instead:

```heex
<button
  id="add-rel-back-to-choose-from-search-btn"
  type="button"
  phx-click="back_to_choose"
  phx-target={@myself}
  class="flex items-center gap-1 text-sm text-ds-primary/70 hover:text-ds-primary mb-3 transition-colors"
>
  <.icon name="hero-arrow-left" class="w-4 h-4" /> Back
</button>
```

- [ ] **Step 6: Update the `:quick_create` step's back button**

The existing "Back to search" button (currently `id="cancel-quick-create-btn"`) should now go back to `:choose` rather than `:search`. Change its `phx-click` to `back_to_choose` and update the label to "Back".

- [ ] **Step 7: Run the tests to verify they pass**

```bash
mix test test/user_flows/link_person_test.exs   # or the new file
```

Expected: PASS.

- [ ] **Step 8: Manual verification**

Walk through the modal in a dev session: tree placeholder → modal opens at `:choose` → both buttons work → both back buttons return to `:choose` → no stale state survives navigation.

- [ ] **Step 9: `mix precommit`**

```bash
mix precommit
```

- [ ] **Step 10: Commit**

```bash
git add lib/web/live/shared/add_relationship_component.ex test/user_flows/
git commit -m "Add :choose step to Add Relationship modal

Splits the modal entry into two equally-weighted options: Link
existing person (search) and Create new person (form). Replaces the
prior pattern where Create new lived as a tertiary link inside the
search step.

Both downstream steps share a back_to_choose handler that clears all
transient state (search_query, search_results, selected_person,
person_form) so navigating back and forth doesn't carry stale state."
```

---

## Task 7: Issue 7 Part C — Refactor `Ancestry.Families.delete_family/1` for safe file cleanup

Prerequisite for the LiveView selection-mode work in Tasks 8-9. This refactor restructures `delete_family/1` so file cleanup runs **after** a successful DB commit, fixing the existing prod S3 leak in addition to enabling batch deletion. The same shape is applied to `delete_organization/1` in this task as well (the contexts are sibling files).

This task also closes a defense-in-depth gap in the `Organization` schema: it currently declares `has_many :families` and `has_many :people` **without** `on_delete: :delete_all`. The DB FKs cascade correctly today (verified at runtime via `Repo.delete(org)` — persons drop alongside the org), but the schema is inconsistent with `Family.galleries`, which declares the option. Adding it costs nothing and is the only remaining safety net if migrations ever change.

**Files:**
- Modify: `lib/ancestry/organizations/organization.ex` (add `on_delete: :delete_all` to both `has_many` declarations)
- Modify: `lib/ancestry/families.ex` (`delete_family/1` + new private helpers)
- Modify: `lib/ancestry/organizations.ex` (`delete_organization/1` + new private helpers)
- Test: `test/ancestry/families_test.exs` (new or extend existing)
- Test: `test/ancestry/organizations_test.exs` (new or extend existing)

- [ ] **Step 0: Add `on_delete: :delete_all` to the Organization schema**

In `lib/ancestry/organizations/organization.ex:8-9`, change:

```elixir
has_many :families, Ancestry.Families.Family
has_many :people, Ancestry.People.Person
```

to:

```elixir
has_many :families, Ancestry.Families.Family, on_delete: :delete_all
has_many :people, Ancestry.People.Person, on_delete: :delete_all
```

This is a no-op at runtime today (the DB FKs already cascade — verified via Tidewave: `persons.organization_id ON DELETE CASCADE`, `families.organization_id ON DELETE CASCADE`) but matches the existing pattern in `Family.galleries` and protects against future migration changes that might drop the DB-level cascade.

No new test required for this step alone — the existing org delete test in Step 6 below verifies cascade behavior end-to-end.

- [ ] **Step 1: Read the current implementations**

```bash
sed -n '20,40p' lib/ancestry/families.ex
sed -n '170,180p' lib/ancestry/families.ex
sed -n '20,32p' lib/ancestry/organizations.ex
```

Confirm:
- `delete_family/1` calls `cleanup_family_files/1` BEFORE `Repo.delete(family)`.
- `cleanup_family_files/1` uses `File.rm_rf` against local upload paths.
- `delete_organization/1` is a one-line `Repo.delete(org)` with no cleanup.

Also read `lib/ancestry/galleries.ex:46-49` to confirm `delete_photo/1`'s Waffle delete pattern:

```elixir
def delete_photo(%Photo{} = photo) do
  if photo.image, do: Ancestry.Uploaders.Photo.delete({photo.image, photo})
  Repo.delete(photo)
end
```

The pattern we want to mimic for cleanup: `if photo.image, do: Ancestry.Uploaders.Photo.delete({photo.image, photo})`.

- [ ] **Step 2: Write failing tests for `delete_family/1`**

In `test/ancestry/families_test.exs` (create if needed):

```elixir
defmodule Ancestry.FamiliesTest do
  use Ancestry.DataCase, async: false  # touches the filesystem
  import Ancestry.Factory

  alias Ancestry.Families
  alias Ancestry.Galleries

  describe "delete_family/1" do
    test "removes the family, its galleries, and its photos via DB cascade" do
      family = insert(:family)
      gallery = insert(:gallery, family: family)
      photo = insert(:photo, gallery: gallery, status: "processed")

      assert {:ok, _} = Families.delete_family(family)

      refute Repo.get(Ancestry.Families.Family, family.id)
      refute Repo.get(Ancestry.Galleries.Gallery, gallery.id)
      refute Repo.get(Ancestry.Galleries.Photo, photo.id)
    end

    test "calls Waffle delete on each photo so the prod S3 leak is fixed" do
      # Use a real local fixture so Waffle.delete actually has something
      # to remove. After delete_family, the file should be gone.
      family = insert(:family)
      gallery = insert(:gallery, family: family)

      photo =
        insert(:photo,
          gallery: gallery,
          status: "processed",
          image: %{file_name: "test_image.jpg", updated_at: nil}
        )

      # Stage a fake file at the path Waffle expects so the delete is observable
      file_path =
        Ancestry.Uploaders.Photo.url({photo.image, photo}, :thumbnail)
        |> String.replace_leading("/", "priv/static/")

      File.mkdir_p!(Path.dirname(file_path))
      File.write!(file_path, "fake")

      assert File.exists?(file_path)
      assert {:ok, _} = Families.delete_family(family)
      refute File.exists?(file_path)
    end

    test "leaves files alone if the DB delete fails" do
      family = insert(:family)
      gallery = insert(:gallery, family: family)
      photo =
        insert(:photo,
          gallery: gallery,
          status: "processed",
          image: %{file_name: "preserve.jpg", updated_at: nil}
        )

      file_path =
        Ancestry.Uploaders.Photo.url({photo.image, photo}, :thumbnail)
        |> String.replace_leading("/", "priv/static/")

      File.mkdir_p!(Path.dirname(file_path))
      File.write!(file_path, "preserve me")

      # Force a DB-level failure: pre-delete the family row directly,
      # then call delete_family with the now-stale struct.
      Repo.delete!(family)

      assert {:error, _} = Families.delete_family(family)
      assert File.exists?(file_path), "file must survive a failed DB delete"

      # cleanup
      File.rm!(file_path)
    end
  end
end
```

- [ ] **Step 3: Run the tests to verify they fail**

```bash
mix test test/ancestry/families_test.exs
```

Expected: FAIL — `delete_family/1` currently leaks Waffle files (cascade deletes photo rows but never invokes Waffle delete). The "leaves files alone if DB delete fails" test currently doesn't even reach the failing branch because cleanup runs first.

- [ ] **Step 4: Refactor `delete_family/1`**

In `lib/ancestry/families.ex`, replace `delete_family/1` and add new private helpers:

```elixir
def delete_family(%Family{} = family) do
  family = Repo.preload(family, galleries: :photos)
  files_to_clean = collect_family_files(family)

  case Repo.delete(family) do
    {:ok, deleted} ->
      cleanup_files(files_to_clean)
      {:ok, deleted}

    {:error, _changeset} = err ->
      err
  end
end

defp collect_family_files(%Family{} = family) do
  photos =
    for gallery <- family.galleries,
        photo <- gallery.photos do
      {:photo, photo}
    end

  local_dirs = [
    Path.join(["priv", "static", "uploads", "families", "#{family.id}"]),
    Path.join(["priv", "static", "uploads", "photos", "#{family.id}"])
  ]

  %{photos: photos, local_dirs: local_dirs}
end

defp cleanup_files(%{photos: photos, local_dirs: dirs}) do
  Enum.each(photos, fn {:photo, photo} ->
    if photo.image do
      try do
        Ancestry.Uploaders.Photo.delete({photo.image, photo})
      rescue
        e -> require Logger; Logger.warning("Photo cleanup failed: #{inspect(e)}")
      end
    end
  end)

  Enum.each(dirs, fn dir ->
    try do
      File.rm_rf(dir)
    rescue
      e -> require Logger; Logger.warning("Local dir cleanup failed: #{inspect(e)}")
    end
  end)

  :ok
end
```

The old `cleanup_family_files/1` private function can be deleted — it's superseded by `cleanup_files/1`.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
mix test test/ancestry/families_test.exs
```

Expected: PASS.

- [ ] **Step 6: Write failing tests for `delete_organization/1`**

In `test/ancestry/organizations_test.exs`:

```elixir
defmodule Ancestry.OrganizationsTest do
  use Ancestry.DataCase, async: false
  import Ancestry.Factory

  alias Ancestry.Organizations

  describe "delete_organization/1" do
    test "removes the org and cascades through families, galleries, photos" do
      org = insert(:organization)
      family = insert(:family, organization: org)
      gallery = insert(:gallery, family: family)
      photo = insert(:photo, gallery: gallery, status: "processed")

      assert {:ok, _} = Organizations.delete_organization(org)

      refute Repo.get(Ancestry.Organizations.Organization, org.id)
      refute Repo.get(Ancestry.Families.Family, family.id)
      refute Repo.get(Ancestry.Galleries.Gallery, gallery.id)
      refute Repo.get(Ancestry.Galleries.Photo, photo.id)
    end

    test "cleans up Waffle photo files for every cascaded photo" do
      org = insert(:organization)
      family = insert(:family, organization: org)
      gallery = insert(:gallery, family: family)

      photo =
        insert(:photo,
          gallery: gallery,
          status: "processed",
          image: %{file_name: "org_test.jpg", updated_at: nil}
        )

      file_path =
        Ancestry.Uploaders.Photo.url({photo.image, photo}, :thumbnail)
        |> String.replace_leading("/", "priv/static/")

      File.mkdir_p!(Path.dirname(file_path))
      File.write!(file_path, "fake")

      assert File.exists?(file_path)
      assert {:ok, _} = Organizations.delete_organization(org)
      refute File.exists?(file_path)
    end
  end
end
```

- [ ] **Step 7: Run the tests to verify they fail**

```bash
mix test test/ancestry/organizations_test.exs
```

Expected: FAIL — current `delete_organization/1` doesn't clean Waffle files.

- [ ] **Step 8: Refactor `delete_organization/1`**

In `lib/ancestry/organizations.ex`, replace `delete_organization/1`:

```elixir
def delete_organization(%Organization{} = org) do
  org = Repo.preload(org, families: [galleries: :photos])
  files_to_clean = collect_org_files(org)

  case Repo.delete(org) do
    {:ok, deleted} ->
      Ancestry.Families.cleanup_files_after_delete(files_to_clean)
      {:ok, deleted}

    {:error, _changeset} = err ->
      err
  end
end

defp collect_org_files(%Organization{} = org) do
  org.families
  |> Enum.reduce(%{photos: [], local_dirs: []}, fn family, acc ->
    family_files = Ancestry.Families.collect_files_for(family)

    %{
      photos: acc.photos ++ family_files.photos,
      local_dirs: acc.local_dirs ++ family_files.local_dirs
    }
  end)
end
```

For this to work, `cleanup_files/1` and `collect_family_files/1` in `lib/ancestry/families.ex` must be promoted from `defp` to `def` (or aliased through public wrappers `cleanup_files_after_delete/1` and `collect_files_for/1`). Pick the minimal exposure: rename `cleanup_files/1` to `cleanup_files_after_delete/1` (`def`) and `collect_family_files/1` to `collect_files_for/1` (`def`), and call the same functions from `delete_family/1`.

- [ ] **Step 9: Update `delete_family/1` to call the renamed public helpers**

```elixir
def delete_family(%Family{} = family) do
  family = Repo.preload(family, galleries: :photos)
  files_to_clean = collect_files_for(family)

  case Repo.delete(family) do
    {:ok, deleted} ->
      cleanup_files_after_delete(files_to_clean)
      {:ok, deleted}

    {:error, _changeset} = err ->
      err
  end
end
```

- [ ] **Step 10: Run all the new context tests**

```bash
mix test test/ancestry/families_test.exs test/ancestry/organizations_test.exs
```

Expected: all PASS.

- [ ] **Step 11: Run existing tests that exercise family/org delete to confirm no regression**

```bash
mix test test/user_flows/delete_family_test.exs
```

Expected: PASS.

- [ ] **Step 12: `mix precommit`**

```bash
mix precommit
```

- [ ] **Step 13: Commit**

```bash
git add lib/ancestry/families.ex lib/ancestry/organizations.ex \
        lib/ancestry/organizations/organization.ex \
        test/ancestry/families_test.exs test/ancestry/organizations_test.exs
git commit -m "Refactor delete_family/delete_organization for safe file cleanup

The previous implementations had two compounding bugs:

1. delete_family/1 ran cleanup_family_files/1 BEFORE Repo.delete, so a
   failed transaction left the DB intact but the files gone.

2. The DB cascade family -> galleries -> photos deletes photo rows via
   raw FK ON DELETE CASCADE, never invoking Galleries.delete_photo/1
   (the only path that calls Waffle.Photo.delete). In production this
   leaked every cascaded photo's S3 versions on every family delete.

   delete_organization/1 was even worse: a one-line Repo.delete with
   zero file cleanup.

The fix: pre-collect all photo structs and local dirs into a manifest,
delete the DB rows in a single Repo.delete call (FK cascade fires),
and only THEN run file cleanup against the manifest. On DB failure
files are untouched.

This fix also benefits the existing single-item delete paths and is a
prerequisite for the upcoming batch-delete UI work."
```

---

## Task 8: Issue 7 — Family index selection-mode batch delete UI

Builds on Task 7's safe `delete_family/1`. Replaces the per-card trash button with a selection-mode UI matching the photo grid pattern.

**Files:**
- Modify: `lib/web/live/family_live/index.ex`
- Modify: `lib/web/live/family_live/index.html.heex`
- Test: `test/user_flows/delete_family_test.exs` (extend) and/or `test/user_flows/family_index_batch_delete_test.exs` (new)

- [ ] **Step 1: Decide test placement**

Read `test/user_flows/delete_family_test.exs`. If short and well-scoped to "delete family from index", extend it with a new batch-delete test case. If it's already covering a different flow (delete from family show), create `test/user_flows/family_index_batch_delete_test.exs`.

- [ ] **Step 2: Write the failing test**

Add a test case (either in the existing file or the new one):

```elixir
# Given multiple families in an organization
# When the user enters selection mode from the family index toolbar
# Then the toolbar Select button changes state
# And cards become selectable

# When the user taps two family cards
# Then both are highlighted as selected
# And the selection bar shows "2 selected"

# When the user taps Delete in the selection bar
# Then a confirmation modal is shown

# When the user confirms
# Then both families are removed from the index
# And selection mode exits
test "batch delete two families via selection mode", %{conn: conn} do
  org = insert(:organization)
  family1 = insert(:family, organization: org, name: "Alpha")
  family2 = insert(:family, organization: org, name: "Beta")
  family3 = insert(:family, organization: org, name: "Gamma")
  account = insert(:account_with_org, organization: org)

  conn = log_in_e2e(conn, account)

  conn =
    conn
    |> visit(~p"/org/#{org.id}")
    |> wait_liveview()

  # Enter selection mode
  conn =
    conn
    |> click(test_id("family-index-select-btn"))
    |> wait_liveview()

  # Tap two cards
  conn =
    conn
    |> click(test_id("family-card-#{family1.id}"))
    |> click(test_id("family-card-#{family2.id}"))
    |> wait_liveview()
    |> assert_has(test_id("selection-bar"), text: "2 selected")

  # Open confirmation
  conn =
    conn
    |> click(test_id("selection-bar-delete-btn"))
    |> wait_liveview()
    |> assert_has(test_id("confirm-delete-families-modal"))

  # Confirm
  conn =
    conn
    |> click(test_id("confirm-delete-families-confirm-btn"))
    |> wait_liveview()

  # Both gone, third still present
  conn
  |> refute_has(test_id("family-card-#{family1.id}"))
  |> refute_has(test_id("family-card-#{family2.id}"))
  |> assert_has(test_id("family-card-#{family3.id}"))

  refute Repo.get(Ancestry.Families.Family, family1.id)
  refute Repo.get(Ancestry.Families.Family, family2.id)
  assert Repo.get(Ancestry.Families.Family, family3.id)
end
```

If the project's E2E helpers don't have an `:account_with_org` factory, mirror what the existing tests use to log in scoped to an org.

- [ ] **Step 3: Run the test to verify it fails**

```bash
mix test test/user_flows/family_index_batch_delete_test.exs   # or wherever you put it
```

Expected: FAIL — selection mode doesn't exist.

- [ ] **Step 4: Add new assigns and event handlers in `family_live/index.ex`**

In `lib/web/live/family_live/index.ex`, in `mount/3` add:

```elixir
|> assign(:selection_mode, false)
|> assign(:selected_ids, MapSet.new())
|> assign(:confirm_delete, false)
```

(Keep the existing `:confirm_delete_family` for now; we'll remove it once the new flow is wired up to avoid leaving the LiveView half-converted.)

Add the new event handlers:

```elixir
def handle_event("toggle_select_mode", _, socket) do
  {:noreply,
   socket
   |> assign(:selection_mode, !socket.assigns.selection_mode)
   |> assign(:selected_ids, MapSet.new())
   |> assign(:confirm_delete, false)}
end

def handle_event("card_clicked", %{"id" => id}, socket) do
  family_id = String.to_integer(id)

  if socket.assigns.selection_mode do
    selected =
      if MapSet.member?(socket.assigns.selected_ids, family_id),
        do: MapSet.delete(socket.assigns.selected_ids, family_id),
        else: MapSet.put(socket.assigns.selected_ids, family_id)

    {:noreply, assign(socket, :selected_ids, selected)}
  else
    {:noreply,
     push_navigate(socket,
       to: ~p"/org/#{socket.assigns.current_scope.organization.id}/families/#{family_id}"
     )}
  end
end

def handle_event("request_batch_delete", _, socket) do
  if MapSet.size(socket.assigns.selected_ids) > 0 do
    {:noreply, assign(socket, :confirm_delete, true)}
  else
    {:noreply, socket}
  end
end

def handle_event("cancel_batch_delete", _, socket) do
  {:noreply, assign(socket, :confirm_delete, false)}
end

def handle_event("confirm_batch_delete", _, socket) do
  selected = MapSet.to_list(socket.assigns.selected_ids)

  results =
    Enum.map(selected, fn id ->
      try do
        family = Ancestry.Families.get_family!(id)
        Ancestry.Families.delete_family(family)
      rescue
        Ecto.NoResultsError -> {:error, :not_found}
      end
    end)

  {oks, errors} = Enum.split_with(results, &match?({:ok, _}, &1))

  org_id = socket.assigns.current_scope.organization.id

  socket =
    socket
    |> assign(:selection_mode, false)
    |> assign(:selected_ids, MapSet.new())
    |> assign(:confirm_delete, false)
    |> stream(:families, Ancestry.Families.list_families(org_id), reset: true)
    |> put_flash_for_results(length(oks), length(errors))

  {:noreply, socket}
end

defp put_flash_for_results(socket, ok_count, 0) do
  put_flash(socket, :info, "Deleted #{pluralize(ok_count, "family", "families")}.")
end

defp put_flash_for_results(socket, _ok_count, error_count) do
  put_flash(
    socket,
    :error,
    "Could not delete #{pluralize(error_count, "family", "families")}. Try again."
  )
end

defp pluralize(1, singular, _plural), do: "1 #{singular}"
defp pluralize(n, _singular, plural), do: "#{n} #{plural}"
```

- [ ] **Step 5: Update `family_live/index.html.heex` toolbar**

Add the Select toggle button to the desktop `hidden lg:flex` group (reuse the gallery's pattern from `gallery_live/show.html.heex:28-43`):

```heex
<div class="hidden lg:flex items-center gap-2">
  <button
    type="button"
    phx-click="toggle_select_mode"
    class={[
      "inline-flex items-center gap-2 rounded-ds-sharp px-4 py-2.5 text-sm font-ds-body font-semibold transition-colors",
      if(@selection_mode,
        do: "bg-ds-primary text-ds-on-primary",
        else: "bg-ds-surface-high text-ds-on-surface hover:bg-ds-surface-highest"
      )
    ]}
    {test_id("family-index-select-btn")}
  >
    <.icon name="hero-check-circle" class="w-4 h-4" />
    <span>{if(@selection_mode, do: "Exit selection", else: "Select")}</span>
  </button>
  <.link ...>People</.link>
  <.link ...>New Family</.link>
</div>
```

Also add the Select action to the nav drawer's `:page_actions` slot (added in Task 2):

```heex
<.nav_action
  icon="hero-check-circle"
  label={if(@selection_mode, do: "Exit selection", else: "Select")}
  phx-click={toggle_nav_drawer() |> JS.push("toggle_select_mode")}
/>
```

- [ ] **Step 6: Replace the family card `<.link>` with `<div phx-click>`**

Currently each family card is wrapped in `<.link navigate={...}>`. Replace with a `<div phx-click="card_clicked" phx-value-id={family.id}>` and a conditional outline ring:

```heex
<div
  :for={{id, family} <- @streams.families}
  id={id}
  class={[
    "group relative bg-ds-surface-card rounded-ds-sharp hover:bg-ds-surface-highest transition-colors overflow-hidden cursor-pointer",
    if(@selection_mode && MapSet.member?(@selected_ids, family.id),
      do: "outline outline-3 outline-ds-primary outline-offset-2",
      else: "outline outline-3 outline-transparent outline-offset-2"
    )
  ]}
  phx-click="card_clicked"
  phx-value-id={family.id}
  {test_id("family-card-#{family.id}")}
>
  <%= if family.cover do %>
    <div class="h-32 overflow-hidden">
      <img ... />
    </div>
  <% else %>
    <div class="h-32 bg-ds-surface-low flex items-center justify-center">
      <.icon name="hero-users" class="w-8 h-8 text-ds-on-surface-variant" />
    </div>
  <% end %>
  <div class="p-4">
    <h2 data-family-name class="text-lg font-ds-heading font-bold text-ds-on-surface truncate">
      {family.name}
    </h2>
    <p class="text-sm text-ds-on-surface-variant mt-1">
      {Calendar.strftime(family.inserted_at, "%B %d, %Y")}
    </p>
  </div>
</div>
```

Note: the per-card trash button (currently inside this same card block) is **deleted** in this step.

- [ ] **Step 7: Add the selection bar**

Insert the selection bar between the toolbar and the cards grid. Reuse the gallery's variant classes (mobile fixed-bottom, desktop inline):

```heex
<%= if @selection_mode do %>
  <div
    id="selection-bar"
    class="fixed bottom-0 left-0 right-0 z-30 bg-ds-surface-card border-t border-ds-outline-variant/20 px-4 py-3 pb-[max(0.75rem,env(safe-area-inset-bottom))] flex items-center justify-between lg:static lg:border-t-0 lg:px-5 lg:py-3 lg:bg-ds-on-surface lg:text-ds-on-primary lg:rounded-ds-sharp lg:mb-4"
    {test_id("selection-bar")}
  >
    <span class="text-sm font-ds-body font-medium text-ds-on-surface lg:text-ds-on-primary">
      {MapSet.size(@selected_ids)} selected
    </span>
    <button
      phx-click="request_batch_delete"
      disabled={MapSet.size(@selected_ids) == 0}
      class="px-3 py-2 text-sm font-ds-body text-ds-error hover:bg-ds-error/10 rounded-ds-sharp transition-colors lg:bg-ds-error lg:text-white lg:hover:opacity-90 disabled:opacity-40 disabled:cursor-not-allowed"
      {test_id("selection-bar-delete-btn")}
    >
      Delete
    </button>
  </div>
<% end %>
```

- [ ] **Step 8: Add the batch confirmation modal**

Replace the existing per-item confirmation modal (currently `family_live/index.html.heex:110-151`) with the batch modal:

```heex
<%= if @confirm_delete do %>
  <div
    id="confirm-delete-families-modal"
    class="fixed inset-0 z-50 flex items-end lg:items-center justify-center"
    phx-window-keydown="cancel_batch_delete"
    phx-key="Escape"
    {test_id("confirm-delete-families-modal")}
  >
    <div class="absolute inset-0 bg-black/60 backdrop-blur-sm" phx-click="cancel_batch_delete"></div>
    <div
      class="relative bg-ds-surface-card/80 backdrop-blur-[20px] shadow-ds-ambient w-full max-w-none lg:max-w-md mx-0 lg:mx-4 rounded-t-lg lg:rounded-ds-sharp p-8"
      role="dialog"
      aria-modal="true"
    >
      <h2 class="text-xl font-ds-heading font-bold text-ds-on-surface mb-2">
        Delete families
      </h2>
      <p class="text-ds-on-surface-variant mb-6 font-ds-body">
        <%= if MapSet.size(@selected_ids) == 1 do %>
          Delete 1 family? All galleries and photos will be permanently removed. This cannot be undone.
        <% else %>
          Delete {MapSet.size(@selected_ids)} families? All galleries and photos will be permanently removed. This cannot be undone.
        <% end %>
      </p>
      <div class="flex gap-3">
        <button
          phx-click="confirm_batch_delete"
          class="flex-1 bg-ds-error text-ds-on-primary rounded-ds-sharp py-2.5 text-sm font-ds-body font-semibold hover:opacity-90 transition-opacity"
          {test_id("confirm-delete-families-confirm-btn")}
        >
          Delete
        </button>
        <button
          phx-click="cancel_batch_delete"
          class="flex-1 bg-ds-surface-high text-ds-on-surface rounded-ds-sharp py-2.5 text-sm font-ds-body font-semibold hover:bg-ds-surface-highest transition-colors"
        >
          Cancel
        </button>
      </div>
    </div>
  </div>
<% end %>
```

- [ ] **Step 9: Remove the old per-item delete handlers and assign**

In `lib/web/live/family_live/index.ex`:
- Delete the `request_delete`, `cancel_delete`, and `confirm_delete` (single-item version) handlers.
- Delete `:confirm_delete_family` from the assigns (no longer used).

In `lib/web/live/family_live/index.html.heex`:
- Remove the per-card trash button (the `<button id="delete-family-#{family.id}">` block) — already done in Step 6.
- The old per-item modal block was already replaced in Step 8.

`grep` for any remaining references to make sure nothing is left:

```bash
grep -n "confirm_delete_family\|request_delete\|delete-family-" lib/web/live/family_live/index.{ex,html.heex}
```

Expected: no matches.

- [ ] **Step 10: Run the failing test to verify it passes**

```bash
mix test test/user_flows/family_index_batch_delete_test.exs   # or wherever
```

Expected: PASS.

- [ ] **Step 11: Update existing `delete_family_test.exs` if needed**

The existing test deletes a family from the family-show toolbar (not from the index), so it should still pass. Verify:

```bash
mix test test/user_flows/delete_family_test.exs
```

Expected: PASS. If it asserts on the per-card trash button on the index, update it to use selection mode instead.

- [ ] **Step 12: Manual verification**

In a dev session:
- Open `/org/<org_id>` with multiple families.
- Tap Select. Confirm cards become selectable and the trash button is gone.
- Tap multiple cards. Confirm the count updates and selected cards have the outline ring.
- Tap Delete. Confirm the modal appears with correct copy (singular vs plural).
- Confirm. Confirm families are removed and stream resets.
- On mobile: confirm the selection bar is fixed to bottom.

- [ ] **Step 13: `mix precommit`**

```bash
mix precommit
```

- [ ] **Step 14: Commit**

```bash
git add lib/web/live/family_live/index.ex lib/web/live/family_live/index.html.heex \
        test/user_flows/
git commit -m "Selection-mode batch delete on family index

Replace the per-card trash button + single-item modal with the
photo-grid selection pattern: a Select toolbar toggle, MapSet of
selected ids, bottom-fixed selection bar showing N selected, and a
batch confirmation modal.

Cards switch from <.link navigate> to <div phx-click> with server-side
branching: in selection mode taps toggle selection; otherwise the
handler push_navigates to the family page. This is necessary because
<.link> swallows clicks before phx-click can branch.

See docs/learnings.jsonl#pure-presentation-components and
docs/learnings.jsonl#update-dependent-assigns."
```

---

## Task 9: Issue 7 — Organization index selection-mode batch delete UI

Mirrors Task 8 on the org index. New deletion capability (the org index had no delete affordance before).

**Files:**
- Modify: `lib/web/live/organization_live/index.ex`
- Modify: `lib/web/live/organization_live/index.html.heex`
- Test: `test/user_flows/org_index_batch_delete_test.exs` (new)

- [ ] **Step 1: Read the org index files**

```bash
cat lib/web/live/organization_live/index.ex
cat lib/web/live/organization_live/index.html.heex
```

Note the existing toolbar has only "New Organization" and the cards are pure `<.link navigate>` with no delete affordance.

- [ ] **Step 2: Write the failing test**

Create `test/user_flows/org_index_batch_delete_test.exs`. Mirror the structure of the family index test from Task 8, adapted to the `/org` route:

```elixir
defmodule Web.UserFlows.OrgIndexBatchDeleteTest do
  use Web.E2ECase

  # Given multiple organizations
  # When the user enters selection mode
  # And taps multiple org cards
  # And confirms deletion
  # Then the orgs are removed and remaining orgs persist

  test "batch delete two organizations via selection mode", %{conn: conn} do
    org1 = insert(:organization, name: "First Org")
    org2 = insert(:organization, name: "Second Org")
    org3 = insert(:organization, name: "Third Org")

    # The acting account must have access to all three; mirror existing tests
    # for the org index login pattern.
    account = insert(:account_with_orgs, organizations: [org1, org2, org3])

    conn = log_in_e2e(conn, account)

    conn =
      conn
      |> visit(~p"/org")
      |> wait_liveview()
      |> click(test_id("org-index-select-btn"))
      |> wait_liveview()
      |> click(test_id("org-card-#{org1.id}"))
      |> click(test_id("org-card-#{org2.id}"))
      |> wait_liveview()
      |> assert_has(test_id("selection-bar"), text: "2 selected")
      |> click(test_id("selection-bar-delete-btn"))
      |> wait_liveview()
      |> assert_has(test_id("confirm-delete-orgs-modal"))
      |> click(test_id("confirm-delete-orgs-confirm-btn"))
      |> wait_liveview()

    refute Repo.get(Ancestry.Organizations.Organization, org1.id)
    refute Repo.get(Ancestry.Organizations.Organization, org2.id)
    assert Repo.get(Ancestry.Organizations.Organization, org3.id)
  end
end
```

If the test setup for "an account that owns multiple orgs" requires more than `insert(:account_with_orgs, ...)`, mirror what `org_manage_people_test.exs` or another existing org test does.

- [ ] **Step 3: Run the test to verify it fails**

```bash
mix test test/user_flows/org_index_batch_delete_test.exs
```

Expected: FAIL.

- [ ] **Step 4: Add assigns and handlers in `organization_live/index.ex`**

Apply the same pattern as Task 8 Step 4. Use `Ancestry.Organizations.delete_organization/1` (refactored in Task 7) and `Ancestry.Organizations.list_organizations/0` for the stream reset. Adapt the `card_clicked` handler's navigation target:

```elixir
def handle_event("card_clicked", %{"id" => id}, socket) do
  org_id = String.to_integer(id)

  if socket.assigns.selection_mode do
    selected =
      if MapSet.member?(socket.assigns.selected_ids, org_id),
        do: MapSet.delete(socket.assigns.selected_ids, org_id),
        else: MapSet.put(socket.assigns.selected_ids, org_id)

    {:noreply, assign(socket, :selected_ids, selected)}
  else
    {:noreply, push_navigate(socket, to: ~p"/org/#{org_id}")}
  end
end
```

`confirm_batch_delete` calls `Ancestry.Organizations.delete_organization(org)`. Pluralize copy says "organization"/"organizations".

- [ ] **Step 5: Update `organization_live/index.html.heex` toolbar**

Add the Select toggle button to the toolbar (mirror Task 8 Step 5; the org toolbar is similar but currently has no `hidden lg:flex` group, only the New Organization button — wrap them together). Add the corresponding `:page_actions` nav drawer entry too.

- [ ] **Step 6: Replace org cards with `<div phx-click>`**

Currently lines 52-66 use `<.link :for={{id, org} <- @streams.organizations}>`. Replace with `<div phx-click="card_clicked" phx-value-id={org.id}>` and conditional outline ring (mirror Task 8 Step 6).

- [ ] **Step 7: Add the selection bar and confirmation modal**

Mirror Task 8 Steps 7 and 8. Modal id: `confirm-delete-orgs-modal`. Copy:
- Singular: `"Delete 1 organization? All families, galleries, and photos will be permanently removed. This cannot be undone."`
- Plural: `"Delete N organizations? All families, galleries, and photos will be permanently removed. This cannot be undone."`

- [ ] **Step 8: Run the test to verify it passes**

```bash
mix test test/user_flows/org_index_batch_delete_test.exs
```

Expected: PASS.

- [ ] **Step 9: Run existing org tests to verify no regression**

```bash
mix test test/user_flows/create_organization_test.exs
```

Expected: PASS.

- [ ] **Step 10: Manual verification**

In a dev session, open `/org` with multiple orgs. Walk through select → multi-select → confirm → verify cascade. Confirm deleted orgs and all their child families/galleries/photos are gone (via psql or `mcp__tidewave__execute_sql_query`).

- [ ] **Step 11: `mix precommit`**

```bash
mix precommit
```

- [ ] **Step 12: Commit**

```bash
git add lib/web/live/organization_live/ test/user_flows/org_index_batch_delete_test.exs
git commit -m "Selection-mode batch delete on organization index

Add brand-new deletion capability to the org index using the same
selection-mode pattern as the family index. Cards switch from
<.link navigate> to <div phx-click> for the same reason.

The org delete cascades through families -> galleries -> photos at the
DB level (verified ON DELETE CASCADE FKs); file cleanup is handled by
the refactored Ancestry.Organizations.delete_organization/1 (post-commit
Waffle/local cleanup)."
```

---

## Task 10: Final pass — append a learning if anything new emerged + final precommit

- [ ] **Step 1: Reflect on what we learned during implementation**

Did anything surprise you that wasn't already in `docs/learnings.jsonl`? Common candidates:
- A subtle bug in `JS.push` value type handling that wasn't obvious from the existing `js-hook-native-types` learning.
- A drawer-close edge case the existing `drawer-action-close-drawer` learning didn't cover.
- A pattern for batching context-layer operations safely with file cleanup that should be its own learning (e.g., "Pre-collect side-effect resources before DB transactions, clean up after commit only").

If yes, add a new entry to `docs/learnings.jsonl` (one JSON object per line, follow the existing schema) and update the index in `docs/learnings.md`. Keep the new entry generic — strip project-specific names.

If nothing new emerged, skip this step.

- [ ] **Step 2: Final precommit**

```bash
mix precommit
```

Expected: clean.

- [ ] **Step 3: Final test sweep**

```bash
mix test
```

Expected: clean. Watch for any `[error]` or `[warning]` log lines in the output (per `docs/learnings.jsonl#clean-test-output`).

- [ ] **Step 4: Final commit (if Step 1 added a learning)**

```bash
git add docs/learnings.jsonl docs/learnings.md
git commit -m "Append learning(s) from mobile fixes implementation"
```

- [ ] **Step 5: Open the PR**

Use the project's existing PR template / convention. Title: `Mobile fixes punch list (Issues 1-7)`. Body should reference both `docs/plans/2026-04-07-mobile-fixes-design.md` and this plan.

---

## Implementation order rationale

| Task | Issue | Risk | Why this order |
|---|---|---|---|
| 1 | 6 | Trivial | One-line delete; warms up the test pipeline |
| 2 | 1 | Low | Pure layout reshuffle; no behavior change |
| 3 | 2 | Low | Two tiny additive fixes; verifies JS hook lifecycle |
| 4 | 5 | Low | Markup-only; sets up the visual baseline for Task 6 |
| 5 | 3 | Medium | State plumbing through three files; first multi-file change |
| 6 | 4 | Medium | Component refactor with new state machine; builds on Task 4 |
| 7 | 7 (Part C) | Medium | Context-layer refactor that's a prerequisite for the LiveView work |
| 8 | 7 (Part A) | Medium | Family index UI on top of the now-safe context |
| 9 | 7 (Part B) | Medium | Org index UI mirrors Task 8 |
| 10 | — | None | Final cleanup, learnings, PR |

Earlier tasks unblock later ones. Tasks 7 → 8 → 9 must run in order (Task 7 is a hard prerequisite). Tasks 1-6 are all independent and could be reordered but the listed order minimizes context switching.

## What if implementation reveals an unanticipated issue?

If you discover that one of the design assumptions doesn't hold (e.g., the `focus_person` handler signature is different than expected, or the cascade delete behaves differently in dev than in test), **stop and surface it** rather than improvising. Update the design doc (`docs/plans/2026-04-07-mobile-fixes-design.md`) with the corrected understanding, then resume from the affected task. Don't silently work around it.
