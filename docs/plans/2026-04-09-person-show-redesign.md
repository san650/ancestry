# Person Show View Redesign — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the person show page to eliminate data duplication, simplify the header, and align margins across all sections.

**Architecture:** Template-only refactor with one new helper function. Desktop header becomes photo + two-line vitals with conditional extra-metadata row below. All page sections share `max-w-4xl`. Mobile keeps hero photo but gets same metadata simplification.

**Tech Stack:** Phoenix LiveView, HEEx templates, Tailwind CSS

**Spec:** `docs/plans/2026-04-09-person-show-redesign-design.md`

---

### Task 1: Add date display helper

**Files:**
- Modify: `lib/web/live/person_live/show.ex`
- Modify: `test/web/live/person_live/show_test.exs`

The new helper combines birth/death dates and deceased status into a single formatted string. It wraps the existing `format_partial_date/3` which handles nil day/month/year.

- [ ] **Step 1: Write failing test for date display helper**

Update the "shows deceased status on detail page" test (line 85) to assert the new format instead of "Deceased: Yes":

```elixir
test "shows deceased status on detail page", %{conn: conn, family: family, org: org} do
  {:ok, deceased_person} =
    People.create_person(family, %{
      given_name: "John",
      surname: "Doe",
      deceased: true,
      death_year: 1994
    })

  {:ok, _view, html} =
    live(conn, ~p"/org/#{org.id}/people/#{deceased_person.id}?from_family=#{family.id}")

  assert html =~ "d. 1994"
  refute html =~ "Deceased:"
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/web/live/person_live/show_test.exs --only line:85`

Expected: FAIL — template still shows "Deceased:" text.

- [ ] **Step 3: Add `format_person_dates/1` helper to show.ex**

Add this private function in `show.ex` after the existing `format_partial_date/3` (line 516):

```elixir
defp format_person_dates(person) do
  birth = format_partial_date(person.birth_day, person.birth_month, person.birth_year)
  death = format_partial_date(person.death_day, person.death_month, person.death_year)

  has_birth = birth != ""
  has_death = death != ""

  cond do
    has_birth and has_death -> "b. #{birth} — d. #{death}"
    has_birth and person.deceased -> "b. #{birth} — deceased"
    has_birth -> "b. #{birth}"
    has_death -> "d. #{death}"
    person.deceased -> "Deceased"
    true -> nil
  end
end
```

Do NOT modify the template yet — this step only adds the helper. The template change comes in Task 2.

- [ ] **Step 4: Commit**

```
feat: add format_person_dates helper for person show
```

### Task 2: Redesign desktop header

**Files:**
- Modify: `lib/web/live/person_live/show.html.heex` (lines 163–297)

This replaces the entire detail view section between `<%!-- Detail view --%>` and `<%!-- Relationships Section --%>` with the new layout.

- [ ] **Step 1: Replace the detail view block**

Replace lines 164–297 (from `<%!-- Hero photo header...` through the closing `</div>` of the `lg:flex` container) with:

```heex
<%!-- Person header: photo + vitals --%>
<div class="max-w-4xl mx-auto">
  <%!-- Desktop layout: photo left, vitals right --%>
  <div class="hidden lg:flex lg:gap-6 lg:px-8 lg:py-6 items-start">
    <%!-- Photo --%>
    <div class="w-48 h-48 shrink-0">
      <%= if @person.photo && @person.photo_status == "processed" do %>
        <img
          src={Ancestry.Uploaders.PersonPhoto.url({@person.photo, @person}, :original)}
          alt={Ancestry.People.Person.display_name(@person)}
          class="w-48 h-48 object-cover rounded-ds-sharp"
        />
      <% else %>
        <div class="w-48 h-48 bg-ds-surface-low flex items-center justify-center rounded-ds-sharp">
          <.icon name="hero-user" class="w-16 h-16 text-ds-on-surface-variant/50" />
        </div>
      <% end %>
    </div>

    <%!-- Vitals --%>
    <div class="pt-1">
      <%= if date_line = format_person_dates(@person) do %>
        <p class="text-[15px] text-ds-on-surface">{date_line}</p>
      <% end %>
      <%= if @person.gender do %>
        <p class="text-sm text-ds-on-surface-variant mt-0.5">{String.capitalize(@person.gender)}</p>
      <% end %>
      <%= if @person.families != [] do %>
        <div class="mt-4 flex gap-1.5 flex-wrap items-center">
          <span class="text-xs text-ds-on-surface-variant/60">In family trees</span>
          <%= for family <- @person.families do %>
            <.link
              navigate={~p"/org/#{@current_scope.organization.id}/families/#{family.id}"}
              class="px-2.5 py-0.5 rounded-full bg-ds-primary/10 text-ds-primary text-xs hover:bg-ds-primary/20 transition-colors"
            >
              {family.name}
            </.link>
          <% end %>
        </div>
      <% end %>
    </div>
  </div>

  <%!-- Mobile layout: hero photo with overlay name, vitals below --%>
  <div class="lg:hidden">
    <div class="relative">
      <%= if @person.photo && @person.photo_status == "processed" do %>
        <img
          src={Ancestry.Uploaders.PersonPhoto.url({@person.photo, @person}, :original)}
          alt={Ancestry.People.Person.display_name(@person)}
          class="w-full max-h-64 object-cover"
        />
      <% else %>
        <div class="w-full h-48 bg-ds-surface-low flex items-center justify-center">
          <.icon name="hero-user" class="w-16 h-16 text-ds-on-surface-variant/50" />
        </div>
      <% end %>
      <div class="absolute bottom-0 left-0 right-0 bg-gradient-to-t from-black/50 to-transparent p-4">
        <h1 class="text-white font-ds-heading text-xl font-bold">
          {Ancestry.People.Person.display_name(@person)}
        </h1>
      </div>
    </div>

    <div class="px-4 py-4 space-y-1">
      <%= if date_line = format_person_dates(@person) do %>
        <p class="text-[15px] text-ds-on-surface">{date_line}</p>
      <% end %>
      <%= if @person.gender do %>
        <p class="text-sm text-ds-on-surface-variant">{String.capitalize(@person.gender)}</p>
      <% end %>
      <%= if @person.families != [] do %>
        <div class="mt-3 flex gap-1.5 flex-wrap items-center">
          <span class="text-xs text-ds-on-surface-variant/60">In family trees</span>
          <%= for family <- @person.families do %>
            <.link
              navigate={~p"/org/#{@current_scope.organization.id}/families/#{family.id}"}
              class="px-2.5 py-0.5 rounded-full bg-ds-primary/10 text-ds-primary text-xs hover:bg-ds-primary/20 transition-colors"
            >
              {family.name}
            </.link>
          <% end %>
        </div>
      <% end %>
    </div>
  </div>

  <%!-- Extra metadata row (both mobile and desktop, only when fields exist) --%>
  <% has_extra =
    has_value?(@person.nickname) or
    has_value?(@person.title) or
    has_value?(@person.suffix) or
    birth_name_differs?(@person.given_name_at_birth, @person.given_name) or
    birth_name_differs?(@person.surname_at_birth, @person.surname) or
    (@person.alternate_names || []) != [] %>

  <%= if has_extra do %>
    <div class="px-4 lg:px-8 py-3 border-t border-ds-surface-low">
      <div class="grid grid-cols-[auto_1fr] gap-x-3 gap-y-1 text-[13px] max-w-[280px]">
        <%= if has_value?(@person.nickname) do %>
          <span class="text-ds-on-surface-variant/60">Nickname</span>
          <span class="text-ds-on-surface">{@person.nickname}</span>
        <% end %>
        <%= if has_value?(@person.title) do %>
          <span class="text-ds-on-surface-variant/60">Title</span>
          <span class="text-ds-on-surface">{@person.title}</span>
        <% end %>
        <%= if has_value?(@person.suffix) do %>
          <span class="text-ds-on-surface-variant/60">Suffix</span>
          <span class="text-ds-on-surface">{@person.suffix}</span>
        <% end %>
        <%= if birth_name_differs?(@person.given_name_at_birth, @person.given_name) do %>
          <span class="text-ds-on-surface-variant/60">Birth given name</span>
          <span class="text-ds-on-surface">{@person.given_name_at_birth}</span>
        <% end %>
        <%= if birth_name_differs?(@person.surname_at_birth, @person.surname) do %>
          <span class="text-ds-on-surface-variant/60">Birth surname</span>
          <span class="text-ds-on-surface">{@person.surname_at_birth}</span>
        <% end %>
      </div>
      <%= if (@person.alternate_names || []) != [] do %>
        <div class="mt-2.5 flex gap-1.5 flex-wrap items-center text-[13px]">
          <span class="text-ds-on-surface-variant/60">Also known as</span>
          <%= for name <- @person.alternate_names do %>
            <span class="px-2 py-0.5 rounded-full bg-ds-surface-low text-ds-on-surface-variant text-xs">
              {name}
            </span>
          <% end %>
        </div>
      <% end %>
    </div>
  <% end %>
</div>
```

- [ ] **Step 2: Run the test to verify the deceased test passes**

Run: `mix test test/web/live/person_live/show_test.exs --only line:85`

Expected: PASS — "Deceased:" no longer in output, "d. 1994" is present.

- [ ] **Step 3: Commit**

```
feat: redesign person show header layout
```

### Task 3: Unify section widths

**Files:**
- Modify: `lib/web/live/person_live/show.html.heex`

- [ ] **Step 1: Update relationships section width**

On line 300, change:
```
class="px-4 py-6 sm:px-6 lg:px-8 lg:max-w-5xl lg:mx-auto"
```
to:
```
class="px-4 py-6 sm:px-6 lg:px-8 max-w-4xl mx-auto"
```

- [ ] **Step 2: Update photos section width**

On line 597 (the `person-photos-section` div), change:
```
class="max-w-7xl mx-auto mt-12"
```
to:
```
class="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 mt-12"
```

- [ ] **Step 3: Run full test suite for this file**

Run: `mix test test/web/live/person_live/show_test.exs`

Expected: All tests pass.

- [ ] **Step 4: Commit**

```
fix: unify person show page section widths to max-w-4xl
```

### Task 4: Run precommit and verify

**Files:** None (verification only)

- [ ] **Step 1: Run precommit**

Run: `mix precommit`

Expected: No warnings, no formatter changes, all tests pass.

- [ ] **Step 2: Visual verification**

Start the dev server with `iex -S mix phx.server` and check:
- Desktop: photo left, vitals right, no name in content, no section headers, extra fields below photo when present, all sections same width
- Mobile: hero photo with name overlay, vitals below, no section headers, extra fields below vitals
- Person with only basic fields: no extra metadata row
- Person with nickname/title/etc: extra metadata row visible
- Deceased person with death date: shows `d. YYYY` not "Deceased: Yes"
- Deceased person without death date: shows "deceased" after birth date
