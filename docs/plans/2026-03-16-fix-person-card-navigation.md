# Fix person_card Navigation Bug — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make `person_card` a pure presentation component so the modal search results trigger `select_person` instead of navigating away.

**Architecture:** Remove the `<.link navigate>` and `family` attr from `person_card`. Each call site wraps the component with the appropriate interaction element (`<.link navigate>`, `<button>`, or nothing). Interactive wrappers carry their own hover/transition classes.

**Tech Stack:** Phoenix LiveView, HEEx templates

**Spec:** `docs/bugfix/specs/2026-03-16-person-card-navigation-bug-design.md`

---

### Task 1: Write the failing test for modal parent selection

**Files:**
- Modify: `test/web/live/person_live/relationships_test.exs`

**Step 1: Write the failing test**

Add a test that exercises the full add-parent-via-modal flow. This test will fail because clicking the search result currently navigates away instead of selecting.

```elixir
test "selects a parent from search results and creates relationship", %{
  conn: conn,
  family: family,
  person: person
} do
  {:ok, candidate} =
    People.create_person(family, %{given_name: "Alice", surname: "Smith", gender: "female"})

  {:ok, view, _html} = live(conn, ~p"/families/#{family.id}/members/#{person.id}")

  # Open add parent modal
  view |> element("#add-parent-btn") |> render_click()
  assert has_element?(view, "#add-relationship-modal")

  # Search for candidate
  view |> element("#relationship-search-input") |> render_keyup(%{value: "Ali"})
  assert has_element?(view, "#search-result-#{candidate.id}")

  # Click the search result — should select, not navigate
  view |> element("#search-result-#{candidate.id}") |> render_click()

  # Should still be on the same page with the selected person shown
  assert has_element?(view, "#add-relationship-modal")

  # Submit the relationship form (role is auto-set to "mother" for female)
  view |> form("#relationship-metadata-form") |> render_submit()

  # Relationship created — modal closed, parent shown
  refute has_element?(view, "#add-relationship-modal")
  assert has_element?(view, "#parents-section")
end
```

**Step 2: Run the test to verify it fails**

Run: `mix test test/web/live/person_live/relationships_test.exs --seed 0`
Expected: FAIL — clicking the search result triggers navigation instead of `select_person`

**Step 3: Commit**

```
git add test/web/live/person_live/relationships_test.exs
git commit -m "Add failing test for parent selection in modal"
```

---

### Task 2: Refactor person_card to pure presentation

**Files:**
- Modify: `lib/web/live/person_live/show.ex` (the `person_card/1` component, around line 538)

**Step 1: Refactor person_card**

Replace the current `person_card` definition (lines 538-579) with a pure presentation component. Remove the `<.link navigate>` wrapper, drop the `family` attr, remove `hover:bg-base-200` and `transition-colors` from the component.

```elixir
defp person_card(assigns) do
  ~H"""
  <div class={[
    "flex items-center gap-3 p-2 rounded-lg",
    @highlighted && "bg-primary/10 border border-primary/20"
  ]}>
    <div class={[
      "w-10 h-10 rounded-full flex-shrink-0 flex items-center justify-center overflow-hidden border-l-4",
      @person.gender == "male" && "border-l-blue-400 bg-blue-50",
      @person.gender == "female" && "border-l-pink-400 bg-pink-50",
      @person.gender not in ["male", "female"] && "border-l-gray-300 bg-base-200"
    ]}>
      <%= if @person.photo && @person.photo_status == "processed" do %>
        <img
          src={Ancestry.Uploaders.PersonPhoto.url({@person.photo, @person}, :thumbnail)}
          alt={Ancestry.People.Person.display_name(@person)}
          class="w-full h-full object-cover"
        />
      <% else %>
        <.icon name="hero-user" class="w-5 h-5 text-base-content/20" />
      <% end %>
    </div>
    <div class="min-w-0 flex-1">
      <p class="font-medium text-sm text-base-content truncate">
        {Ancestry.People.Person.display_name(@person)}
      </p>
      <p class="text-xs text-base-content/50">
        <%= if @person.birth_year do %>
          {@person.birth_year}
          <%= if @person.death_year do %>
            –{@person.death_year}
          <% end %>
        <% end %>
      </p>
    </div>
  </div>
  """
end
```

**Step 2: Compile to verify no errors**

Run: `mix compile --warnings-as-errors`
Expected: Compilation errors — call sites still pass `family` attr

---

### Task 3: Update all call sites in the template

**Files:**
- Modify: `lib/web/live/person_live/show.html.heex`

Update each of the 9 call sites. Remove the `family={@family}` attr from all. Wrap navigable cards in `<.link navigate>` with hover/transition classes. Leave display-only and button-wrapped cards unwrapped.

**Step 1: Update each call site**

**Line 319** — Current person in partner group (display only, highlighted):
```heex
<.person_card person={@person} highlighted={true} />
```

**Line 324** — Partner card (navigable):
```heex
<.link navigate={~p"/families/#{@family.id}/members/#{partner.id}"} class="flex-1 rounded-lg transition-colors hover:bg-base-200">
  <.person_card person={partner} highlighted={false} />
</.link>
```
Also remove the wrapping `<div class="flex-1">` since `<.link>` now carries `flex-1`.

**Line 396** — Child in partner group (navigable):
```heex
<.link navigate={~p"/families/#{@family.id}/members/#{child.id}"} class="rounded-lg transition-colors hover:bg-base-200">
  <.person_card person={child} highlighted={false} />
</.link>
```

**Line 423** — Solo child (navigable):
```heex
<.link navigate={~p"/families/#{@family.id}/members/#{child.id}"} class="rounded-lg transition-colors hover:bg-base-200">
  <.person_card person={child} highlighted={false} />
</.link>
```

**Line 460** — Parent card (navigable):
```heex
<.link navigate={~p"/families/#{@family.id}/members/#{parent.id}"} class="flex-1 rounded-lg transition-colors hover:bg-base-200">
  <.person_card person={parent} highlighted={false} />
</.link>
```
Also remove the wrapping `<div class="flex-1">` since `<.link>` now carries `flex-1`.

**Line 524** — Current person in siblings (display only, highlighted):
```heex
<.person_card person={@person} highlighted={true} />
```

**Line 528** — Sibling card (navigable):
```heex
<.link navigate={~p"/families/#{@family.id}/members/#{sibling_person(sib).id}"} class="flex-1 rounded-lg transition-colors hover:bg-base-200">
  <.person_card person={sibling_person(sib)} highlighted={false} />
</.link>
```
Also remove the wrapping `<div class="flex-1">` since `<.link>` now carries `flex-1`.

**Line 642** — Search result in modal (button, the bug fix):
```heex
<button
  id={"search-result-#{result.id}"}
  phx-click="select_person"
  phx-value-id={result.id}
  class="w-full text-left rounded-lg transition-colors hover:bg-base-200"
>
  <.person_card person={result} highlighted={false} />
</button>
```

**Line 658** — Selected person confirmation (display only, highlighted):
```heex
<.person_card person={@selected_person} highlighted={true} />
```

**Step 2: Compile**

Run: `mix compile --warnings-as-errors`
Expected: PASS — no warnings, no errors

**Step 3: Commit**

```
git add lib/web/live/person_live/show.ex lib/web/live/person_live/show.html.heex
git commit -m "Refactor person_card to pure presentation, fix modal navigation bug"
```

---

### Task 4: Run all tests and verify

**Step 1: Run the full test suite**

Run: `mix test`
Expected: All tests pass, including the new modal selection test from Task 1.

**Step 2: Run precommit checks**

Run: `mix precommit`
Expected: All checks pass (compile, format, tests).

**Step 3: Commit any formatting fixes if needed**

---

### Task 5: Write learnings

**Files:**
- Modify: `docs/learnings.md`

**Step 1: Add learning entry**

Add a new section to `docs/learnings.md`:

```markdown
## Reusable components should not embed navigation behavior

When a component like `person_card` wraps its content in `<.link navigate={...}>`, it cannot be reused in contexts where a different click behavior is needed (e.g., a `<button phx-click="select_person">` in a modal). The `<.link navigate>` fires client-side navigation before any `phx-click` on a parent element reaches the server, causing the page to navigate away unexpectedly.

**Fix:** Make reusable display components pure presentation (`<div>` wrappers, no click behavior). Let each call site decide the interaction: `<.link navigate>` for navigation, `<button phx-click>` for events, or nothing for display-only contexts. This follows the principle of separating presentation from behavior.
```

**Step 2: Commit**

```
git add docs/learnings.md
git commit -m "Add learning: reusable components should not embed navigation"
```
