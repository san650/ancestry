# Mobile fixes punch list — design

**Date:** 2026-04-07
**Status:** Design — awaiting implementation plan
**Scope:** Seven independent UX fixes across mobile (and a couple cross-platform), plus a corrective refactor of family/organization deletion that surfaced during spec review. Single bundled PR.

## Goals

Fix a punch list of mobile UX issues uncovered after the mobile-first migration, plus a small number of cross-platform follow-ups. Each item is independent; ordering inside the implementation plan should reflect risk (data-touching items last) rather than topical grouping.

## Non-goals

- Redesigning toolbars, drawers, or the tree view from scratch.
- Touching the photo processing pipeline or S3 storage beyond what's needed to plug the orphan-files leak surfaced during review.
- Adding new permissions, roles, or organization-level capabilities beyond batch deletion.
- Changing the desktop tree-view side panel behavior.
- Removing the gallery uniform/masonry layout toggle (considered and explicitly declined).

## Background

After the mobile-first migration (#10), several pages and flows still don't follow the established mobile pattern, and a few small bugs surfaced. The user enumerated a punch list during brainstorming. The items are unrelated in code paths but small enough to ship together. Spec review surfaced a separate latent issue: deleting a family or organization leaks the cascaded photos' S3 versions in production today, and the proposed batch-delete inherits that bug. Fixing it properly is folded into Issue 7.

The canonical mobile patterns this design refers back to:

- **Toolbar pattern** — `lib/web/live/family_live/show.html.heex:1-121` and `lib/web/live/gallery_live/show.html.heex:1-73`. Toolbars use `py-2`, action groups wrapped in `hidden lg:flex` (desktop only), and a parallel `:page_actions` slot inside the nav drawer for mobile.
- **Drawer auto-close pattern** — `lib/web/live/family_live/show.html.heex:125-150`. Actions inside the drawer chain `toggle_nav_drawer()` with `JS.push("event", value: %{...})` so the click both closes the drawer and dispatches the event.
- **Photo selection pattern** — `lib/web/live/gallery_live/show.ex:75-133` and `lib/web/live/gallery_live/show.html.heex:28-43, 134-151`. A select toggle button in the toolbar, `:selection_mode` boolean assign + `:selected_ids` `MapSet`, bottom-fixed selection bar with "N selected" + "Delete", confirmation modal.

## Issues

### Issue 1 — `FamilyLive.Index` toolbar follows the mobile pattern

**Files:** `lib/web/live/family_live/index.html.heex`

**Current state.** The toolbar (lines 2-35) wraps in `max-w-7xl mx-auto`, uses `py-4`, and renders the "People" + "New Family" buttons on every breakpoint. On mobile, "New Family" wraps to two lines and the right-hand action group crowds the title.

**Change.**

- Remove the inner `max-w-7xl` wrapper.
- Tighten padding from `py-4` to `py-2`.
- Wrap the existing People + New Family link group in `hidden lg:flex` so it only renders on desktop.
- Add a `:page_actions` slot to the nav drawer with two `<.nav_action>` entries:
  - `icon="hero-users"`, `label="People"`, navigates to the org people index.
  - `icon="hero-plus"`, `label="New family"`, navigates to the new family form.

The mobile-only deletion controls added in Issue 7 also live in this toolbar; sequence in implementation matters (Issue 1 first, Issue 7 builds on it).

**Reference:** `docs/learnings.jsonl#mobile-toolbar-pattern`.

### Issue 2 — Gallery FAB unresponsive after lightbox close

**Files:** `lib/web/live/gallery_live/show.html.heex`, `assets/js/photo_tagger.js`

**Symptom (clarified during review).** On mobile: open the gallery, tap a photo, the lightbox opens, close the lightbox, then tap the bottom-left back-FAB → nothing happens. The FAB itself (the custom back arrow) is broken; this is not about the browser back button.

**Root cause (corrected from initial diagnosis).** Spec review surfaced that `assets/js/photo_tagger.js:8` short-circuits on viewports under 1024px:

```js
mounted() {
  if (window.innerWidth < 1024) return
  // ... container creation never runs on mobile
}
```

So the original "stale `#tag-circles` / `#tag-popover` overlays swallow the FAB click" theory cannot apply on mobile — those containers are never created in the first place. However, `destroyed()` (`photo_tagger.js:267-275`) runs unconditionally and references `this._raf`, `this.circlesContainer`, and `this.popoverContainer` — all `undefined` on mobile because `mounted` early-returned. **Every lightbox close on mobile throws a `TypeError` from the hook teardown path**, leaving LiveView's hook lifecycle in a bad state.

**Change (three small parts).**

1. **Hide the FAB while the lightbox is open.** Add `:if={is_nil(@selected_photo)}` (or wrap in `<%= unless ... %>`) on the FAB so it isn't rendered when the lightbox is showing. The lightbox already has its own X close button — the FAB has nothing to do while a photo is maximized. This eliminates the visual overlap and removes any z-index concerns entirely.
2. **Guard `PhotoTagger.destroyed()`.** Add `if (!this.circlesContainer) return` (or equivalent) at the top of `destroyed()` so the unmount path doesn't throw on mobile. This is the actual root-cause fix.
3. **(No more z-index bump and no more "idempotent mounted()" change.** Both were dropped after the review showed the original diagnosis was wrong. The FAB hide and the destroyed guard cover the symptom.)

**Verification.** Implementer should reproduce the bug on a mobile viewport before changing anything, confirm the JS error in the console after closing the lightbox, then apply the destroyed guard and confirm the error is gone and the FAB is responsive after lightbox close. The FAB-hide change is verifiable visually.

**Risk.** Low. Both changes are tiny and additive.

### Issue 3 — Close mobile nav drawer when a person is focused

**Files:** `lib/web/live/family_live/people_list_component.ex`, `lib/web/live/family_live/side_panel_component.ex`, `lib/web/live/family_live/show.html.heex`

**Symptom.** On mobile, the family tree view exposes the people list inside the nav drawer (`family/show.html.heex:152-163`, the `:page_panel` slot). Tapping a person fires the `focus_person` event, but the drawer stays open, so the user cannot see the just-focused person in the tree behind the drawer.

**Mounting chain (corrected from initial design).** `PeopleListComponent` is **not** mounted directly by the family-show template. The chain is:

```
family/show.html.heex (drawer :page_panel slot)
  → SidePanelComponent
    → PeopleListComponent
```

Both the desktop side panel and the mobile drawer mount `SidePanelComponent`. So the "close drawer on select" behavior must be threaded through `SidePanelComponent` as a passthrough attribute, then forwarded to `PeopleListComponent`.

**Change.**

1. Add a `close_drawer_on_select` boolean attr (default `false`) to `PeopleListComponent`. The row button at `people_list_component.ex:70-93` renders its `phx-click` based on the flag:
   - `false` → `phx-click="focus_person" phx-value-id={person.id}` (current behavior).
   - `true` → `phx-click={toggle_nav_drawer() |> JS.push("focus_person", value: %{id: person.id})}`.
2. Add the same `close_drawer_on_select` attr to `SidePanelComponent` and pass it through to its inner `<.live_component module={PeopleListComponent} ... close_drawer_on_select={@close_drawer_on_select} />` mount.
3. In `family/show.html.heex`, set `close_drawer_on_select={true}` on the **drawer** instance (line 153) and `false` (or omit) on the **desktop** instance (line 254).
4. In `people_list_component.ex`, add `alias Phoenix.LiveView.JS` and `import Web.Components.NavDrawer, only: [toggle_nav_drawer: 0]` (or whichever import path exposes `toggle_nav_drawer`). Verify the helper is exported before adding.

**Pitfall to verify (P1 from spec review): `js-hook-native-types`.** The current `focus_person` handler (`family_live/show.ex:105`) was written against `phx-value-id`, which always arrives as a string. After this change, the same handler will receive `JS.push("focus_person", value: %{id: person.id})` — and `JS.push` values may arrive as native types depending on the Phoenix version. The implementer must:

- Read `family_live/show.ex:105` before implementing.
- If the handler does `String.to_integer(id)` and `id` arrives as integer, it crashes.
- Fix by either (a) `value: %{id: to_string(person.id)}` at the JS.push site, or (b) make the handler accept both via `id |> to_string() |> String.to_integer()`.

Option (a) is the safer default — it keeps the handler unchanged and matches existing string-id contracts.

**References:** `docs/learnings.jsonl#drawer-action-close-drawer`, `docs/learnings.jsonl#js-hook-native-types`, `docs/learnings.jsonl#pure-presentation-components`.

### Issue 4 — Split "Link existing person" / "Create new person" in Add Relationship modal

**Files:** `lib/web/live/shared/add_relationship_component.ex`

**Current state.** Two existing entry steps:

- `:search` (lines 211-258 approximately — verify before editing) — search input, results list, plus a tertiary "Person not listed? Create new" button at the bottom that switches to `:quick_create`.
- `:quick_create` (lines 259-292 approximately) — first/last name form, with a "Back to search" button.

Searching ("link an existing person") and creating mix on the same screen, with creation feeling like an afterthought.

**Change.** Add a new initial step `:choose` that presents two equal entry actions:

- **Link existing person** → switches to `:search`.
- **Create new person** → switches to `:quick_create`.

The component starts at `:choose` (was `:search`). Both `:search` and `:quick_create` get a "Back" button that returns to `:choose` (replacing the current "Back to search" on `:quick_create`). The "Person not listed? Create new" tertiary link is removed from `:search` since "Create new" is now a top-level option.

Initial assign change in `update/2`: `assign_new(:step, fn -> :choose end)`. Add a `back_to_choose` event that resets `:step` to `:choose` and clears `:search_query`, `:search_results`, `:person_form`, **and** `:selected_person` (so navigating back and forth doesn't carry stale state into the next attempt).

The `:metadata` step (the confirmation step shown after a person is selected, lines 293+) is unchanged. Both flows still funnel into it.

### Issue 5 — Compact, height-limited search results in Add Relationship modal

**Files:** `lib/web/live/shared/add_relationship_component.ex`

**Current state.** Search results (`add_relationship_component.ex:228-241`) use `space-y-1 max-h-60 overflow-y-auto` with full `person_card_inline` rows (~3rem tall). Roughly 3 rows fit before scroll.

**Change.** Inline a compact row markup specifically for the search results list:

- Avatar `w-6 h-6` (matches the existing `PersonSelectorComponent` row style — implementer should consider whether `PersonSelectorComponent`'s row markup can be reused as a private helper rather than duplicated).
- Single-line truncated name (`text-ds-on-surface text-sm`).
- `py-1.5 px-2`, ~2.25rem total row height.
- Container `max-h-44 overflow-y-auto` so exactly four rows are visible before scroll.

`person_card_inline` continues to be used in the `:metadata` confirmation step, where its full layout makes sense.

### Issue 6 — Settings page no longer requires sudo mode

**Files:** `lib/web/live/account_live/settings.ex`

**Current state.** Line 4: `on_mount {Web.AccountAuth, :require_sudo_mode}`. The `:require_sudo_mode` callback (`account_auth.ex:233-246`) requires that the account authenticated within the last 10 minutes; otherwise it redirects to `/accounts/log-in`. Net effect: visiting settings while logged in but past the 10-minute window prompts a re-login.

**Important context (S1 from spec review).** The router already wraps the settings routes in a `live_session` whose `on_mount` is `:require_authenticated`:

```elixir
# lib/web/router.ex:86-90
live_session :require_authenticated_account,
  on_mount: [{Web.AccountAuth, :require_authenticated}] do
  live "/accounts/settings", AccountLive.Settings, :edit
  live "/accounts/settings/confirm-email/:token", AccountLive.Settings, :confirm_email
end
```

The module-level `on_mount {Web.AccountAuth, :require_sudo_mode}` in `settings.ex:4` is **additive** — it stacks on top of the router-level `:require_authenticated`.

**Change.** **Delete** the module-level `on_mount` line entirely (one line removed, not replaced). The router-level `:require_authenticated` from `live_session :require_authenticated_account` continues to enforce that the account is logged in. The result: logged-in accounts go straight to settings; unauthenticated requests are still redirected to login by the router-level hook.

**Threat model accepted.** A stolen-but-stale session token can change the account email or password without a fresh login. Documented in `docs/learnings.jsonl#audit-generated-auth-defaults`. The `:require_sudo_mode` callback stays defined in `account_auth.ex` for possible future use on higher-stakes routes; it just isn't called.

**No other changes.** The login redirect, the password update controller path (`/accounts/update-password`), and the sudo helper code itself are untouched.

**References:** `docs/learnings.jsonl#audit-generated-auth-defaults`, `docs/learnings.jsonl#router-on-mount-hooks`.

### Issue 7 — Selection-mode batch deletion for organizations and families (with a corrective file-cleanup refactor)

**Files:** `lib/web/live/family_live/index.{ex,html.heex}`, `lib/web/live/organization_live/index.{ex,html.heex}`, `lib/ancestry/families.ex`, `lib/ancestry/organizations.ex`, `lib/ancestry/organizations/organization.ex`, `lib/ancestry/galleries.ex` (verify; may need a small list helper)

**Current state.**

- `family_live/index.html.heex:97-104` has a per-card trash button + a single-item confirmation modal at lines 110-151. Deletion is one-at-a-time, with a top-right trash icon on each family card.
- `organization_live/index.html.heex` has no deletion affordance at all. Org cards are pure `<.link navigate>`.
- `Ancestry.Families.delete_family/1` (`families.ex:27-30`) calls `cleanup_family_files/1` (a `File.rm_rf` against local upload directories) **before** `Repo.delete(family)`. The cascade `family → galleries → photos` deletes photo rows via raw FK `on_delete: :delete_all` — never touching `Galleries.delete_photo/1`, which is the only path that calls `Waffle.Photo.delete` (S3 cleanup).
- `Ancestry.Organizations.delete_organization/1` (`organizations.ex:24-26`) is a one-line `Repo.delete(org)` with no cleanup at all.
- **Net effect today:** Deleting a family in production leaks every photo's S3 versions. Deleting an organization leaks even more (the entire family-tree's worth of photos plus any local files).

**Goals of this issue (combined).**

A. Replace per-card single-item deletion on the family index with the photo-grid selection pattern.
B. Add brand-new selection-mode deletion to the organization index.
C. **Fix the latent file-orphan bug** in `delete_family/1` and `delete_organization/1` so the new batch path doesn't inherit it. This is the larger of the three.

#### Part C — file cleanup refactor + schema consistency fix (do this first)

The current single-item delete is broken in two compounding ways:

1. Local file cleanup runs **before** the DB delete, so a transaction failure leaves the DB intact but the files gone (unrecoverable).
2. Cascade deletes via FK `on_delete: :delete_all` skip `Galleries.delete_photo/1`, so S3-stored photo files are never cleaned up in production.

Additionally — surfaced during plan review — the `Organization` schema declares `has_many :families` and `has_many :people` **without** the `on_delete: :delete_all` option, while the `Family` schema declares it for `has_many :galleries`. The DB-level FKs cascade correctly today (verified at runtime: `persons.organization_id` and `families.organization_id` are both `ON DELETE CASCADE` in Postgres), but the schema annotation is the only safety net if a future migration changes the FK definition. Adding the option to both `has_many` declarations on `Organization` matches the existing pattern and provides defense in depth at zero cost.

**Pattern (apply to both `delete_family/1` and `delete_organization/1`):**

```elixir
# Step 1: Pre-collect all files to delete (without touching them yet).
# Walk the cascade tree and capture the {:waffle_struct, ...} tuples
# and local directory paths that will need cleanup AFTER the DB commit.

# Step 2: Delete DB rows in a single transaction.
# Use Repo.delete (cascades fire) inside Repo.transaction or Multi.

# Step 3: On {:ok, _}, run all file cleanup (Waffle delete for S3,
#   File.rm_rf for local dirs). Failures here are logged, not fatal —
#   the DB is consistent and the worst case is leftover files.
# On {:error, _}, do NOT run any cleanup. The DB rolled back, the files
#   were untouched, the user can retry.
```

**Concrete shape for `delete_family/1`:**

```elixir
def delete_family(%Family{} = family) do
  family = Repo.preload(family, galleries: :photos)
  files_to_clean = collect_family_files(family)

  case Repo.delete(family) do
    {:ok, family} ->
      cleanup_files(files_to_clean)  # best-effort, logs on error
      {:ok, family}
    {:error, _} = err -> err
  end
end

defp collect_family_files(family) do
  photo_files =
    for gallery <- family.galleries, photo <- gallery.photos do
      {:waffle_photo, photo}
    end

  local_dirs = [
    Path.join(["priv", "static", "uploads", "families", "#{family.id}"]),
    Path.join(["priv", "static", "uploads", "photos", "#{family.id}"])
  ]

  %{photos: photo_files, local_dirs: local_dirs}
end

defp cleanup_files(%{photos: photos, local_dirs: dirs}) do
  Enum.each(photos, fn {:waffle_photo, photo} ->
    if photo.image, do: Ancestry.Uploaders.Photo.delete({photo.image, photo})
  end)
  Enum.each(dirs, &File.rm_rf/1)
end
```

**For `delete_organization/1`:** Same pattern, but the preload walks one level deeper:

```elixir
def delete_organization(%Organization{} = org) do
  org = Repo.preload(org, families: [galleries: :photos])
  files_to_clean = collect_org_files(org)

  case Repo.delete(org) do
    {:ok, org} ->
      cleanup_files(files_to_clean)
      {:ok, org}
    {:error, _} = err -> err
  end
end
```

(`collect_org_files/1` aggregates per-family `collect_family_files/1` results.)

**Side effect:** This also fixes the existing single-item deletion bug. The current `family/index` per-item delete also leaks S3 files in prod today; the refactor fixes that for free. The fact that the refactor lives in the context module rather than the LiveView means both single-item and batch paths get the fix.

#### Part A/B — selection mode UI on both index pages

**Toolbar.** Both pages get a new `Select` toggle button:

- Icon: `hero-check-circle` (matches the photo grid).
- Desktop: lives in the toolbar's `hidden lg:flex` group alongside other actions.
- Mobile: lives in the nav drawer `:page_actions` slot (added by Issue 1 for `family/index`; added new for `organization/index`).
- When `:selection_mode` is on, the icon styling switches to `bg-ds-primary text-ds-on-primary` and the label becomes `Exit selection`.
- **Event name: `toggle_select_mode`** (matching `gallery_live/show.ex:75`, not `toggle_select`).

**Assigns.** Both LiveViews gain:

- `:selection_mode` (boolean, default `false`).
- `:selected_ids` (default `MapSet.new()`).
- `:confirm_delete` (boolean, default `false`).

**Toggle handler** must reset all dependent state in the same `assign` chain (per `docs/learnings.jsonl#update-dependent-assigns`):

```elixir
def handle_event("toggle_select_mode", _, socket) do
  {:noreply,
   socket
   |> assign(:selection_mode, !socket.assigns.selection_mode)
   |> assign(:selected_ids, MapSet.new())
   |> assign(:confirm_delete, false)
   |> stream(:families, list_families(...), reset: true)}  # or :organizations
end
```

**Card behavior — the `<.link navigate>` decision (C4 from review).**

Family and org cards currently wrap content in `<.link navigate>`. Per `docs/learnings.jsonl#pure-presentation-components`, wrapping reusable display content in `<.link navigate>` prevents adding alternate click behavior (selection toggle) — the navigate fires before `phx-click` reaches the server. Selection mode forces the cleanup.

**Change:** Replace the `<.link navigate>` wrapper on each card with a `<div phx-click="card_clicked" phx-value-id={...}>`. The handler branches server-side:

```elixir
def handle_event("card_clicked", %{"id" => id}, socket) do
  if socket.assigns.selection_mode do
    handle_event("toggle_select", %{"id" => id}, socket)
  else
    {:noreply, push_navigate(socket, to: ~p"/org/#{id}")}  # or family path
  end
end
```

The cards lose `<.link>`'s prefetch optimization in the read-only common case. This is a small cost; navigation is still fast enough that it's invisible in practice and consistent with how the photo grid handles its tile clicks (`photo_gallery.ex:38-50`).

When `:selection_mode == true`, selected cards get an outline ring (`outline outline-3 outline-ds-primary outline-offset-2`, mirroring the photo grid).

The per-card trash button on the family index (`family_live/index.html.heex:97-104`) is **removed** entirely. Selection mode is the sole deletion path.

**Removal cleanup.** Issue 7 also removes from `family_live/index.{ex,html.heex}`:

- The per-card trash button markup at `family_live/index.html.heex:97-104`.
- The single-item confirmation modal markup at `family_live/index.html.heex:110-151`.
- The `:confirm_delete_family` assign in `family_live/index.ex`.
- The `request_delete` and `cancel_delete` event handlers (replaced by the batch `confirm_delete` / `cancel_delete` handlers below).

The implementer should grep `family_live/index.ex` for `confirm_delete_family` to make sure no leftover references survive.

**Selection bar.** Bottom-fixed on mobile, inline at top of grid on desktop. Mirrors `gallery_live/show.html.heex:134-151`:

- Left: `"#{MapSet.size(@selected_ids)} selected"`.
- Right: `Delete` button, disabled when nothing is selected.
- Pressing Delete sets `:confirm_delete = true`.

**Confirmation modal.** Stable id (`id="confirm-delete-families-modal"` or `confirm-delete-orgs-modal`, never derived from selection state — per `docs/learnings.jsonl#stable-livecomponent-ids`). Same structure as `confirm-delete-photos-modal`. Copy with simple pluralization helper:

- Family index, single: `"Delete 1 family? All galleries and photos will be permanently removed. This cannot be undone."`
- Family index, plural: `"Delete N families? All galleries and photos will be permanently removed. This cannot be undone."`
- Org index, single: `"Delete 1 organization? All families, galleries, and photos will be permanently removed. This cannot be undone."`
- Org index, plural: `"Delete N organizations? All families, galleries, and photos will be permanently removed. This cannot be undone."`

A small private helper in each LiveView (or a shared `Web.Plural` if duplication grows) computes the singular/plural form: `pluralize(count, singular, plural)`.

**Server-side delete.** Both LiveViews iterate the selected ids and call the new `delete_family/1` / `delete_organization/1` (now safe per Part C above). All-or-nothing per-batch is **not** the contract — the contract is "each item is fully cleaned up or fully not, and we report any partial failure to the user." Implementation:

```elixir
def handle_event("confirm_delete", _, socket) do
  selected = MapSet.to_list(socket.assigns.selected_ids)

  results =
    Enum.map(selected, fn id ->
      family = Families.get_family!(id)  # rescue Ecto.NoResultsError if needed
      Families.delete_family(family)
    end)

  {oks, errors} = Enum.split_with(results, &match?({:ok, _}, &1))

  socket =
    socket
    |> assign(:selection_mode, false)
    |> assign(:selected_ids, MapSet.new())
    |> assign(:confirm_delete, false)
    |> stream(:families, list_families(...), reset: true)
    |> put_flash_for_results(oks, errors)

  {:noreply, socket}
end
```

(`put_flash_for_results/3` is a small helper that puts an :info flash on full success and an :error flash listing failed counts on partial failure.)

**Note: this reverses the brainstorm-time "all-or-nothing Multi" decision.** The reversal is forced by the file-cleanup refactor in Part C: file deletion happens after each individual `Repo.delete` commits, so a single Multi cannot wrap the file cleanup — and trying to put file deletes inside a Multi recreates the original "files gone, DB rolled back" bug. The per-item-then-collect approach is also consistent with `gallery_live/show.ex:118-133`'s existing batch photo delete pattern.

**Cross-platform.** Selection mode works on both mobile and desktop, just like the photo grid. The selection bar adapts (`fixed bottom-0` mobile, inline desktop) using the same Tailwind variants as the gallery selection bar.

**References:** `docs/learnings.jsonl#pure-presentation-components`, `#update-dependent-assigns`, `#stable-livecomponent-ids`.

## Affected files (summary)

| File | Issue(s) | Nature |
|---|---|---|
| `lib/web/live/family_live/index.html.heex` | 1, 7 | Toolbar restructure, drawer page_actions, replace `<.link>` cards with `<div phx-click>`, selection mode markup, remove per-card trash + modal |
| `lib/web/live/family_live/index.ex` | 7 | New assigns, selection event handlers, batch delete loop, stream reset, remove `:confirm_delete_family` and `request_delete`/`cancel_delete` |
| `lib/web/live/organization_live/index.html.heex` | 7 | Toolbar Select button (desktop + drawer), replace `<.link>` cards with `<div phx-click>`, selection mode markup, selection bar, confirmation modal |
| `lib/web/live/organization_live/index.ex` | 7 | New assigns, selection event handlers, batch delete loop, stream reset |
| `lib/web/live/gallery_live/show.html.heex` | 2 | FAB rendered only when lightbox closed |
| `assets/js/photo_tagger.js` | 2 | Guard `destroyed()` against undefined containers |
| `lib/web/live/family_live/people_list_component.ex` | 3 | New `close_drawer_on_select` attr, conditional `phx-click`, JS imports |
| `lib/web/live/family_live/side_panel_component.ex` | 3 | Pass-through `close_drawer_on_select` attr |
| `lib/web/live/family_live/show.html.heex` | 3 | Pass `close_drawer_on_select={true}` to drawer instance only |
| `lib/web/live/shared/add_relationship_component.ex` | 4, 5 | New `:choose` step, back_to_choose event clearing all transient state, compact search row markup, height-limited results container |
| `lib/web/live/account_live/settings.ex` | 6 | Delete the module-level `on_mount` line |
| `lib/ancestry/families.ex` | 7 | Refactor `delete_family/1` to do file cleanup AFTER successful DB commit; new private helpers `collect_family_files/1`, `cleanup_files/1` |
| `lib/ancestry/organizations.ex` | 7 | Refactor `delete_organization/1` to do file cleanup AFTER successful DB commit; new `collect_org_files/1` |

## Tests

Per `test/user_flows/CLAUDE.md`, every new or changed user *flow* needs an interaction-driven test. Pure layout reshuffles and one-line auth swaps don't qualify (they have no behavior change to assert against). Required new tests:

1. `test/user_flows/gallery_back_button_after_lightbox_test.exs` — Issue 2. Open the gallery, open a photo, close the lightbox, tap the back FAB, assert navigation back to the family page. Also asserts the FAB is not in the DOM while the lightbox is open.
2. `test/user_flows/tree_drawer_closes_on_focus_test.exs` — Issue 3. Open the family tree, open the mobile drawer, tap a person in the people list, assert the drawer is closed and the focused person is rendered in the tree.
3. `test/user_flows/add_relationship_choose_step_test.exs` — Issue 4. Trigger add-parent from a tree placeholder, assert the new `:choose` step renders, exercise both paths (Link → search → select; Create → quick_create → save), assert back-to-choose returns to the chooser without stale state.
4. `test/user_flows/family_index_batch_delete_test.exs` — Issue 7 (family). Enter selection mode, select multiple families, confirm delete, assert remaining stream and (in dev) absence of leftover files. Also covers the partial-failure path.
5. `test/user_flows/org_index_batch_delete_test.exs` — Issue 7 (org). Same coverage on the organization index, including the cascade through families/galleries/photos.

**Tests intentionally not added** (not user-flow changes):

- Issue 1 toolbar restructure — pure layout reshuffle, the People and New Family actions still exist and still work; the toolbar regression would surface in any other family-index test that interacts with them. If any existing test asserts on toolbar markup positions, update it.
- Issue 5 compact-row visual constraint — pixel heights are not flow assertions. Manual verification is appropriate.
- Issue 6 settings access — folded into the existing settings test (if any) by adding a stale-session case. If no existing settings test exists, add a single test case asserting that a logged-in account beyond the sudo window loads `/accounts/settings` without being redirected.

`mix precommit` must be clean before completion.

## Decisions

Captured during brainstorming and spec review so they don't need to be re-derived:

- **Gallery layout toggle (declined).** Removing the uniform/masonry toggle on mobile was considered and dropped. The desktop toggle stays untouched and the mobile entry stays as-is.
- **Issue 2 — actual root cause and fix.** First diagnosis (stale `PhotoTagger` overlays + z-index conflict) was wrong; spec review showed `PhotoTagger.mounted()` early-returns on mobile. Real bug: `destroyed()` references undefined fields and throws `TypeError` on every lightbox close on mobile, corrupting LiveView's hook teardown. Fix: hide the FAB while lightbox is open + guard `destroyed()`. Z-index bump dropped.
- **Issue 3 — drawer-close mechanism.** Pass a flag through the shared component, render the chained `JS` command in markup. Matches existing pattern. (Rejected: server-side `push_event("close_nav_drawer")`.)
- **Issue 3 — integration point correction.** Spec review caught that `PeopleListComponent` is mounted by `SidePanelComponent`, not directly by the family-show template. The flag threads through `SidePanelComponent`.
- **Issue 6 — auth tradeoff and execution.** Remove sudo mode entirely. The router-level live_session already enforces `:require_authenticated`, so the fix is to **delete** the module-level `on_mount` line, not replace it. Documented in `docs/learnings.jsonl#audit-generated-auth-defaults`.
- **Issue 7 — `<.link>` cards become `<div phx-click>`.** Necessary because `<.link navigate>` swallows clicks before `phx-click` can branch on selection mode. Justified by `docs/learnings.jsonl#pure-presentation-components`. Costs: loss of `<.link>` prefetch in the read-only common case; gain: a single uniform card markup with server-side branching, matching how the photo grid handles its tiles.
- **Issue 7 — file cleanup is fixed properly, not papered over.** The current single-item delete leaks S3 files in production today (`delete_family` runs cleanup BEFORE the DB delete and only handles local files; cascade deletes for photos never call `Galleries.delete_photo` / Waffle). The refactor restructures `delete_family/1` and `delete_organization/1` to do file cleanup AFTER successful commit, addressing both the existing leak and the batch use case in one move.
- **Issue 7 — per-item-then-collect, not all-or-nothing Multi.** This reverses the brainstorm-time decision. Forced by the file-cleanup refactor: file delete must run after each individual commit, so a wrapping Multi can't be the boundary without recreating the "files gone, DB rolled back" bug. Consistent with `gallery_live/show.ex:118-133`'s existing batch photo delete pattern.
- **Issue 7 — confirmation copy uses simple singular/plural helper.** Avoids `(s)` ugliness.
- **Issue 7 — pattern coverage.** Selection mode is desktop + mobile, mirroring the photo grid. Per-card trash buttons and per-item modals on the family index are removed.

## Risks & open questions

- **Issue 7 cascade verification.** Before implementing Part C, run `get_ecto_schemas` (Tidewave) and confirm:
  - `Family` has `has_many :galleries, on_delete: :delete_all`
  - `Gallery` has `has_many :photos, on_delete: :delete_all`
  - `Organization` has `has_many :families, on_delete: :delete_all`
  - DB-level FK constraints match (run `execute_sql_query` on `pg_constraint` if needed).

  If any cascade is missing, fix it as part of this work — do not paper over it. If the schema cascades are unexpectedly different from the migrations (e.g. one was added later without updating the schema annotation), surface to the user before proceeding.
- **Issue 7 batch size.** Reasonable family-photo workloads should never select more than a handful of orgs/families at once. No pagination or batching limit added. Each delete triggers a preload that walks galleries → photos; selecting an org with thousands of photos will load thousands of photo structs into memory before deletion. Acceptable for the expected scale; flag if it becomes a problem.
- **Issue 3 verification (P1).** Before merging, verify the `focus_person` handler in `family_live/show.ex:105` accepts whatever `JS.push("focus_person", value: %{id: person.id})` actually delivers. Stringify at the call site as the safer default.

## Out of scope (deferred)

- A more thorough refactor of `add_relationship_component.ex` (it's 544 lines and growing).
- Reworking the side-panel layout on desktop.
- Adding bulk actions for photos beyond the existing delete.
- Generic permission/authorization checks for deletion (the project currently has no per-org-per-account permission model; deletion is account-scoped via `Web.EnsureOrganization`).
