# Birthday Calendar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a vertical birthday calendar page, family-scoped, that lists family members by birth month/day with auto-scroll to today, faded past entries, and age display.

**Architecture:** New LiveView (`Web.BirthdayLive.Index`) with a context query (`Ancestry.People.list_birthdays_for_family/1`), a small JS hook for auto-scroll, and a meatball menu link from the family show page. No new schemas or migrations needed.

**Tech Stack:** Phoenix LiveView, Ecto, Tailwind CSS, gettext, JS hook

**Spec:** `docs/plans/2026-04-15-birthday-calendar-design.md`

---

### Task 1: Context query — `list_birthdays_for_family/1`

**Files:**
- Modify: `lib/ancestry/people.ex`
- Test: `test/ancestry/people_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
# In test/ancestry/people_test.exs
describe "list_birthdays_for_family/1" do
  setup do
    family = insert(:family)
    %{family: family}
  end

  test "returns people with both birth_month and birth_day, ordered by month then day", %{family: family} do
    may_person = insert(:person, given_name: "May", birth_month: 5, birth_day: 10, organization: family.organization)
    jan_person = insert(:person, given_name: "Jan", birth_month: 1, birth_day: 15, organization: family.organization)
    Ancestry.People.add_to_family(may_person, family)
    Ancestry.People.add_to_family(jan_person, family)

    result = Ancestry.People.list_birthdays_for_family(family.id)
    assert [first, second] = result
    assert first.id == jan_person.id
    assert second.id == may_person.id
  end

  test "excludes people missing birth_month or birth_day", %{family: family} do
    no_month = insert(:person, given_name: "NoMonth", birth_day: 5, birth_month: nil, organization: family.organization)
    no_day = insert(:person, given_name: "NoDay", birth_month: 3, birth_day: nil, organization: family.organization)
    complete = insert(:person, given_name: "Complete", birth_month: 6, birth_day: 1, organization: family.organization)
    for p <- [no_month, no_day, complete], do: Ancestry.People.add_to_family(p, family)

    result = Ancestry.People.list_birthdays_for_family(family.id)
    assert length(result) == 1
    assert hd(result).id == complete.id
  end

  test "excludes people not in the family", %{family: family} do
    other_family = insert(:family, organization: family.organization)
    in_family = insert(:person, given_name: "In", birth_month: 3, birth_day: 1, organization: family.organization)
    not_in_family = insert(:person, given_name: "Out", birth_month: 3, birth_day: 2, organization: family.organization)
    Ancestry.People.add_to_family(in_family, family)
    Ancestry.People.add_to_family(not_in_family, other_family)

    result = Ancestry.People.list_birthdays_for_family(family.id)
    assert length(result) == 1
    assert hd(result).id == in_family.id
  end

  test "filters out invalid date combinations like Feb 30", %{family: family} do
    valid = insert(:person, given_name: "Valid", birth_month: 2, birth_day: 28, organization: family.organization)
    invalid = insert(:person, given_name: "Invalid", birth_month: 2, birth_day: 30, organization: family.organization)
    for p <- [valid, invalid], do: Ancestry.People.add_to_family(p, family)

    result = Ancestry.People.list_birthdays_for_family(family.id)
    assert length(result) == 1
    assert hd(result).id == valid.id
  end

  test "includes Feb 29 (leap day) birthdays", %{family: family} do
    leap = insert(:person, given_name: "Leap", birth_month: 2, birth_day: 29, organization: family.organization)
    Ancestry.People.add_to_family(leap, family)

    result = Ancestry.People.list_birthdays_for_family(family.id)
    assert length(result) == 1
    assert hd(result).id == leap.id
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ancestry/people_test.exs --seed 0`
Expected: FAIL — `list_birthdays_for_family/1` is undefined

- [ ] **Step 3: Write minimal implementation**

Add to `lib/ancestry/people.ex`:

```elixir
def list_birthdays_for_family(family_id) do
  Repo.all(
    from p in Person,
      join: fm in FamilyMember,
      on: fm.person_id == p.id and fm.family_id == ^family_id,
      where: not is_nil(p.birth_month) and not is_nil(p.birth_day),
      where: fragment("""
        ? <= CASE ?
          WHEN 1 THEN 31 WHEN 2 THEN 29 WHEN 3 THEN 31 WHEN 4 THEN 30
          WHEN 5 THEN 31 WHEN 6 THEN 30 WHEN 7 THEN 31 WHEN 8 THEN 31
          WHEN 9 THEN 30 WHEN 10 THEN 31 WHEN 11 THEN 30 WHEN 12 THEN 31
        END
        """, p.birth_day, p.birth_month),
      order_by: [asc: p.birth_month, asc: p.birth_day]
  )
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/ancestry/people_test.exs --seed 0`
Expected: All 5 new tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/people.ex test/ancestry/people_test.exs
git commit -m "feat: add list_birthdays_for_family/1 query"
```

---

### Task 2: Route and LiveView skeleton

**Files:**
- Modify: `lib/web/router.ex`
- Create: `lib/web/live/birthday_live/index.ex`

- [ ] **Step 1: Add the route**

In `lib/web/router.ex`, inside the `:organization` live_session, after the kinship route, add:

```elixir
live "/families/:family_id/birthdays", BirthdayLive.Index, :index
```

- [ ] **Step 2: Create the LiveView skeleton**

Create `lib/web/live/birthday_live/index.ex`:

```elixir
defmodule Web.BirthdayLive.Index do
  use Web, :live_view

  alias Ancestry.Families
  alias Ancestry.People
  alias Ancestry.People.Person

  @impl true
  def mount(%{"family_id" => family_id}, _session, socket) do
    family = Families.get_family!(family_id)

    if family.organization_id != socket.assigns.current_scope.organization.id do
      raise Ecto.NoResultsError, queryable: Ancestry.Families.Family
    end

    today = Date.utc_today()
    people = People.list_birthdays_for_family(family_id)
    months = group_by_month(people, today)

    {:ok,
     socket
     |> assign(:family, family)
     |> assign(:months, months)
     |> assign(:today, today)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-lg mx-auto px-4 py-6">
        <div class="flex items-center gap-3 mb-6">
          <.link
            navigate={~p"/org/#{@current_scope.organization.id}/families/#{@family.id}"}
            class="p-1 text-ds-on-surface-variant hover:text-ds-on-surface"
            aria-label={gettext("Back to family")}
          >
            <.icon name="hero-arrow-left" class="size-5" />
          </.link>
          <h1 class="font-ds-heading font-bold text-lg text-ds-on-surface">
            {gettext("Birthdays")}
          </h1>
        </div>

        <div id="birthday-calendar">
          <%= for month <- @months do %>
            <div class="mb-6">
              <div class={[
                "sticky top-0 z-10 py-2 px-3 bg-ds-surface-low/80 backdrop-blur-sm border-b border-ds-outline-variant/30 mb-2",
                month.is_past && "opacity-50"
              ]}>
                <span class="font-ds-heading font-bold text-sm text-ds-on-surface">
                  {month.name}
                </span>
              </div>

              <%= if month.entries == [] do %>
                <p class="text-sm text-ds-on-surface-variant/60 px-3 py-4">
                  {gettext("No birthdays")}
                </p>
              <% else %>
                <%= for entry <- month.entries do %>
                  <%= if entry == :today_marker do %>
                    <div
                      id="today-marker"
                      class="flex items-center gap-2 my-3 px-3"
                      phx-hook="ScrollToToday"
                    >
                      <div class="flex-1 h-0.5 bg-[#006d35]"></div>
                      <span class="text-[10px] font-bold text-[#006d35] tracking-wider whitespace-nowrap">
                        {gettext("TODAY")} · {format_today(@today)}
                      </span>
                      <div class="flex-1 h-0.5 bg-[#006d35]"></div>
                    </div>
                  <% else %>
                    <.link
                      navigate={~p"/org/#{@current_scope.organization.id}/people/#{entry.person.id}?from_family=#{@family.id}"}
                      class={[
                        "flex items-center gap-3 px-3 py-2.5 rounded-lg bg-ds-surface-low/50 mb-1.5 hover:bg-ds-surface-high transition-colors",
                        entry.is_past && "opacity-45"
                      ]}
                      {test_id("birthday-entry-#{entry.person.id}")}
                    >
                      <%!-- Date box --%>
                      <div class="flex-shrink-0 bg-ds-surface-highest rounded-lg px-2.5 py-1.5 text-center min-w-[48px]">
                        <div class="text-lg font-bold text-ds-on-surface leading-none">
                          {entry.person.birth_day}
                        </div>
                        <div class="text-[9px] font-semibold text-ds-on-surface-variant uppercase tracking-wider">
                          {month_abbrev(entry.person.birth_month)}
                        </div>
                      </div>
                      <%!-- Avatar --%>
                      <div class="w-9 h-9 rounded-full bg-ds-surface-high flex items-center justify-center overflow-hidden flex-shrink-0">
                        <%= if entry.person.photo && entry.person.photo_status == "processed" do %>
                          <img
                            src={Ancestry.Uploaders.PersonPhoto.url({entry.person.photo, entry.person}, :thumbnail)}
                            alt={Person.display_name(entry.person)}
                            class="w-full h-full object-cover"
                          />
                        <% else %>
                          <.icon name="hero-user" class={["w-4 h-4", gender_icon_class(entry.person.gender)]} />
                        <% end %>
                      </div>
                      <%!-- Name + age --%>
                      <div class="flex-1 min-w-0">
                        <div class="text-[13px] font-medium text-ds-on-surface truncate">
                          {Person.display_name(entry.person)}
                          <%= if entry.person.deceased do %>
                            <span class="text-[10px] font-normal text-ds-on-surface-variant">
                              ({gettext("deceased")})
                            </span>
                          <% end %>
                        </div>
                        <%= if entry.age_label do %>
                          <div class="text-[11px] text-ds-on-surface-variant">
                            {entry.age_label}
                          </div>
                        <% end %>
                      </div>
                    </.link>
                  <% end %>
                <% end %>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # --- Helpers ---

  defp group_by_month(people, today) do
    people_by_month = Enum.group_by(people, & &1.birth_month)

    for month_num <- 1..12 do
      month_people = Map.get(people_by_month, month_num, [])
      is_past_month = month_num < today.month

      entries = build_entries(month_people, month_num, today)

      %{
        number: month_num,
        name: month_name(month_num),
        is_past: is_past_month && !Enum.any?(entries, &(&1 == :today_marker)),
        entries: entries
      }
    end
  end

  defp build_entries(people, month_num, today) do
    entries =
      Enum.map(people, fn person ->
        is_past = birthday_is_past?(person.birth_month, person.birth_day, today)

        %{
          person: person,
          is_past: is_past,
          age_label: age_label(person, today)
        }
      end)

    if month_num == today.month do
      {past, future} = Enum.split_with(entries, & &1.is_past)
      past ++ [:today_marker] ++ future
    else
      entries
    end
  end

  defp birthday_is_past?(birth_month, birth_day, today) do
    # Leap day edge case: on non-leap years, treat Feb 29 as Feb 28
    effective_day =
      if birth_month == 2 and birth_day == 29 and not Date.leap_year?(today) do
        28
      else
        birth_day
      end

    {birth_month, effective_day} < {today.month, today.day}
  end

  defp compute_age(birth_year, birth_month, birth_day, today) do
    base_age = today.year - birth_year
    if {today.month, today.day} < {birth_month, birth_day}, do: base_age - 1, else: base_age
  end

  defp age_label(%{birth_year: nil}, _today), do: nil

  defp age_label(person, today) do
    age = compute_age(person.birth_year, person.birth_month, person.birth_day, today)

    is_today =
      {person.birth_month, person.birth_day} == {today.month, today.day} or
        (person.birth_month == 2 and person.birth_day == 29 and
           not Date.leap_year?(today) and today.month == 2 and today.day == 28)

    cond do
      person.deceased ->
        gettext("Would have turned %{age}", age: age)

      is_today ->
        gettext("Turns %{age} today!", age: age)

      birthday_is_past?(person.birth_month, person.birth_day, today) ->
        gettext("Turned %{age}", age: age)

      true ->
        gettext("Turns %{age}", age: age)
    end
  end

  defp month_name(1), do: gettext("January")
  defp month_name(2), do: gettext("February")
  defp month_name(3), do: gettext("March")
  defp month_name(4), do: gettext("April")
  defp month_name(5), do: gettext("May")
  defp month_name(6), do: gettext("June")
  defp month_name(7), do: gettext("July")
  defp month_name(8), do: gettext("August")
  defp month_name(9), do: gettext("September")
  defp month_name(10), do: gettext("October")
  defp month_name(11), do: gettext("November")
  defp month_name(12), do: gettext("December")

  defp month_abbrev(1), do: gettext("Jan")
  defp month_abbrev(2), do: gettext("Feb")
  defp month_abbrev(3), do: gettext("Mar")
  defp month_abbrev(4), do: gettext("Apr")
  defp month_abbrev(5), do: gettext("May")
  defp month_abbrev(6), do: gettext("Jun")
  defp month_abbrev(7), do: gettext("Jul")
  defp month_abbrev(8), do: gettext("Aug")
  defp month_abbrev(9), do: gettext("Sep")
  defp month_abbrev(10), do: gettext("Oct")
  defp month_abbrev(11), do: gettext("Nov")
  defp month_abbrev(12), do: gettext("Dec")

  defp format_today(date) do
    "#{month_abbrev(date.month) |> String.upcase()} #{date.day}"
  end

  defp gender_icon_class("male"), do: "text-blue-400"
  defp gender_icon_class("female"), do: "text-pink-400"
  defp gender_icon_class(_), do: "text-ds-primary"
end
```

- [ ] **Step 3: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: Compiles with no errors

- [ ] **Step 4: Commit**

```bash
git add lib/web/router.ex lib/web/live/birthday_live/index.ex
git commit -m "feat: add birthday calendar LiveView and route"
```

---

### Task 3: JS hook — ScrollToToday

**Files:**
- Create: `assets/js/scroll_to_today.js`
- Modify: `assets/js/app.js`

- [ ] **Step 1: Create the hook**

Create `assets/js/scroll_to_today.js`:

```javascript
export const ScrollToToday = {
  mounted() {
    this.el.scrollIntoView({ behavior: "smooth", block: "center" })
  }
}
```

- [ ] **Step 2: Register the hook in app.js**

In `assets/js/app.js`, add the import near the other imports:

```javascript
import { ScrollToToday } from "./scroll_to_today"
```

Add `ScrollToToday` to the hooks object:

```javascript
hooks: { ...colocatedHooks, FuzzyFilter, TreeConnector, PhotoTagger, PersonHighlight, Swipe, TrixEditor, ScrollToToday },
```

- [ ] **Step 3: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: No errors. The hook is wired up.

- [ ] **Step 4: Commit**

```bash
git add assets/js/scroll_to_today.js assets/js/app.js
git commit -m "feat: add ScrollToToday JS hook for birthday calendar"
```

---

### Task 4: Meatball menu link from family show

**Files:**
- Modify: `lib/web/live/family_live/show.html.heex`

- [ ] **Step 1: Add the birthdays link to the meatball menu**

In `lib/web/live/family_live/show.html.heex`, inside the meatball dropdown `<div>`, after the "Manage people" `<.link>` block (the one with `hero-user-group` icon) and before the "Create subfamily" conditional block, add:

```heex
<.link
  navigate={~p"/org/#{@current_scope.organization.id}/families/#{@family.id}/birthdays"}
  class="flex items-center gap-3 px-4 py-2.5 text-sm text-ds-on-surface hover:bg-ds-surface-low transition-colors"
  {test_id("family-birthdays-btn")}
>
  <.icon name="hero-cake" class="size-4 text-ds-on-surface-variant" />
  <span>{gettext("Birthdays")}</span>
</.link>
```

- [ ] **Step 2: Verify compilation**

Run: `mix compile --warnings-as-errors`
Expected: No errors

- [ ] **Step 3: Commit**

```bash
git add lib/web/live/family_live/show.html.heex
git commit -m "feat: add birthdays link to family meatball menu"
```

---

### Task 5: E2E tests

**Files:**
- Create: `test/user_flows/birthday_calendar_test.exs`

- [ ] **Step 1: Write the E2E tests**

Create `test/user_flows/birthday_calendar_test.exs`:

```elixir
defmodule Web.UserFlows.BirthdayCalendarTest do
  @moduledoc """
  Birthday calendar flow

  Given a family with people who have birth dates
  When the user navigates to the birthday calendar from the family meatball menu
  Then a vertical calendar is shown with months January through December
  And people are listed under their birth month ordered by day
  And a "TODAY" marker divides past from upcoming birthdays
  And deceased people are tagged with "(deceased)"
  And people without birth month/day are excluded
  And clicking a person navigates to their profile
  """
  use Web.E2ECase

  setup do
    family = insert(:family, name: "Birthday Family")
    org = Ancestry.Organizations.get_organization!(family.organization_id)

    # Person with birthday in January (past, assuming test runs after Jan)
    jan_person =
      insert(:person,
        given_name: "January",
        surname: "Person",
        birth_month: 1,
        birth_day: 15,
        birth_year: 1990,
        organization: family.organization
      )

    Ancestry.People.add_to_family(jan_person, family)

    # Deceased person with birthday in March
    deceased_person =
      insert(:person,
        given_name: "March",
        surname: "Deceased",
        birth_month: 3,
        birth_day: 20,
        birth_year: 1940,
        deceased: true,
        organization: family.organization
      )

    Ancestry.People.add_to_family(deceased_person, family)

    # Person with birthday in December (future)
    dec_person =
      insert(:person,
        given_name: "December",
        surname: "Person",
        birth_month: 12,
        birth_day: 25,
        birth_year: 2000,
        organization: family.organization
      )

    Ancestry.People.add_to_family(dec_person, family)

    # Person without complete birth date (excluded)
    no_birthday =
      insert(:person,
        given_name: "NoBirthday",
        surname: "Person",
        birth_month: nil,
        birth_day: nil,
        organization: family.organization
      )

    Ancestry.People.add_to_family(no_birthday, family)

    %{
      family: family,
      org: org,
      jan_person: jan_person,
      deceased_person: deceased_person,
      dec_person: dec_person,
      no_birthday: no_birthday
    }
  end

  test "view birthday calendar from family menu", %{
    conn: conn,
    family: family,
    org: org,
    jan_person: jan_person,
    deceased_person: deceased_person,
    dec_person: dec_person,
    no_birthday: no_birthday
  } do
    conn =
      conn
      |> log_in_e2e(organization_ids: [org.id])
      |> PhoenixTest.visit(~p"/org/#{org.id}/families/#{family.id}")
      |> wait_liveview()

    # Open meatball menu and click birthdays
    conn =
      conn
      |> click(test_id("meatball-btn"))
      |> click(test_id("family-birthdays-btn"))
      |> wait_liveview()

    # All 12 months are shown
    conn
    |> assert_has("span", text: "January")
    |> assert_has("span", text: "December")

    # Empty month placeholder
    |> assert_has("p", text: "No birthdays")

    # January person shown
    |> assert_has(test_id("birthday-entry-#{jan_person.id}"), text: "January Person")

    # Deceased tagged
    |> assert_has(test_id("birthday-entry-#{deceased_person.id}"), text: "deceased")

    # December person shown
    |> assert_has(test_id("birthday-entry-#{dec_person.id}"), text: "December Person")

    # NoBirthday person excluded
    |> refute_has(test_id("birthday-entry-#{no_birthday.id}"))

    # Today marker is present
    |> assert_has("#today-marker")

    # Click a person navigates to their profile
    conn
    |> click(test_id("birthday-entry-#{dec_person.id}"))
    |> wait_liveview()
    |> assert_has("h1", text: "December Person")
  end
end
```

- [ ] **Step 2: Run the E2E test**

Run: `mix test test/user_flows/birthday_calendar_test.exs`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add test/user_flows/birthday_calendar_test.exs
git commit -m "test: add E2E test for birthday calendar flow"
```

---

### Task 6: Gettext extraction and precommit

**Files:**
- Modify: `priv/gettext/es/LC_MESSAGES/default.po` (translations)

- [ ] **Step 1: Extract gettext strings**

Run: `mix gettext.extract --merge`

This will add all new strings (month names, age labels, "Birthdays", "No birthdays", "TODAY", "deceased") to the `.pot` and `.po` files.

- [ ] **Step 2: Add Spanish translations**

Edit `priv/gettext/es/LC_MESSAGES/default.po` and add translations for the new strings:

- "Birthdays" → "Cumpleaños"
- "No birthdays" → "Sin cumpleaños"
- "TODAY" → "HOY"
- "deceased" → "fallecido/a"
- "Back to family" → "Volver a la familia"
- "Turned %{age}" → "Cumplió %{age}"
- "Turns %{age}" → "Cumple %{age}"
- "Turns %{age} today!" → "¡Cumple %{age} hoy!"
- "Would have turned %{age}" → "Habría cumplido %{age}"
- Month names: "January" → "Enero", "February" → "Febrero", etc.
- Month abbreviations: "Jan" → "Ene", "Feb" → "Feb", "Mar" → "Mar", "Apr" → "Abr", "May" → "May", "Jun" → "Jun", "Jul" → "Jul", "Aug" → "Ago", "Sep" → "Sep", "Oct" → "Oct", "Nov" → "Nov", "Dec" → "Dic"

- [ ] **Step 3: Run precommit**

Run: `mix precommit`
Expected: Compiles (warnings-as-errors), formats, tests pass.

- [ ] **Step 4: Commit**

```bash
git add priv/gettext/
git commit -m "feat: add Spanish translations for birthday calendar"
```

---

### Task 7: Final verification

- [ ] **Step 1: Run full test suite**

Run: `mix test`
Expected: All tests pass

- [ ] **Step 2: Run precommit**

Run: `mix precommit`
Expected: Clean pass

- [ ] **Step 3: Manual smoke test**

Run: `iex -S mix phx.server`

1. Navigate to a family that has people with birth dates
2. Open the meatball menu → click "Birthdays"
3. Verify: all 12 months visible, people listed by birthday, today marker visible, past entries faded, clicking a person navigates to their profile
