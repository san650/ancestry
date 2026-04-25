# Acquaintance Person Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `kind` enum field to Person (`"family_member"` / `"acquaintance"`) so non-family people can exist in the system for photo tagging and memory mentions without cluttering the tree view or relationship graph.

**Architecture:** A single `kind` column on the `persons` table controls behavior at the context and LiveView layers. Acquaintances belong to families (via `FamilyMember`) but are excluded from tree view, relationship dropdowns, and kinship selectors. Conversion between kinds is a field update with guards (no relationships allowed for acquaintances).

**Tech Stack:** Elixir, Phoenix LiveView, Ecto, PostgreSQL

**Spec:** `docs/plans/2026-04-24-acquaintance-person-design.md`

---

## File Map

**Create:**
- `priv/repo/migrations/TIMESTAMP_add_kind_to_persons.exs` — migration
- `test/ancestry/people/person_kind_test.exs` — unit tests for kind field, changeset, helpers
- `test/user_flows/acquaintance_person_test.exs` — E2E tests

**Modify:**
- `lib/ancestry/people/person.ex` — add `kind` field, cast, validation, helper
- `lib/ancestry/people.ex` — rename `list_people_for_family/1` → `list_people/1`, add `list_family_members/1`, filter search functions, guard `set_default_member/2`, add `convert_to_acquaintance/1` (with Ecto.Multi to clear default) and `convert_to_family_member/1`
- `lib/ancestry/relationships.ex` — guard `create_relationship/4` against acquaintances, add `count_relationships/1`
- `lib/ancestry/people/family_graph.ex:23` — use `list_family_members/1`
- `lib/web/live/family_live/show.ex:32,720` — use `list_family_members/1` (mount + `refresh_graph`)
- `lib/web/live/family_live/print.ex:20` — use `list_family_members/1`
- `lib/web/live/person_live/index.ex:21` — use `list_people/1` (sidebar shows all kinds)
- `lib/web/live/shared/person_form_component.html.heex` — add acquaintance checkbox
- `lib/web/live/person_live/show.ex` — add convert events, conditionally load relationships
- `lib/web/live/person_live/show.html.heex` — hide relationships section for acquaintances, add convert banner/dropdown
- `lib/web/live/people_live/index.ex` — add `acquaintance_only` filter, scope `unlinked_only` to family members
- `lib/web/live/people_live/index.html.heex` — add "Non-family" badge + filter chip
- `lib/web/live/org_people_live/index.ex` — add `acquaintance_only` filter, scope `no_family_only` to family members
- `lib/web/live/org_people_live/index.html.heex` — add "Non-family" badge + filter chip
- `lib/web/live/kinship_live.ex` — use `list_family_members/1`, filter acquaintances in `filter_people/3`
- `test/support/factory.ex` — add `acquaintance_factory` and `family_member_factory`
- `test/ancestry/import/csv_test.exs` — update `list_people_for_family` calls to `list_people`
- `test/ancestry/families/create_family_from_person_test.exs` — update `list_people_for_family` calls
- `priv/gettext/es-UY/LC_MESSAGES/default.po` — Spanish translations

---

### Task 1: Migration + Schema

Add the `kind` field to the database and Person schema.

**Files:**
- Create: `priv/repo/migrations/TIMESTAMP_add_kind_to_persons.exs`
- Modify: `lib/ancestry/people/person.ex:6-54,56-68`
- Test: `test/ancestry/people/person_kind_test.exs`

- [ ] **Step 1: Write failing tests for kind field**

Create `test/ancestry/people/person_kind_test.exs`:

```elixir
defmodule Ancestry.People.PersonKindTest do
  use Ancestry.DataCase, async: true

  alias Ancestry.People.Person

  describe "changeset/2 kind field" do
    test "defaults kind to family_member" do
      changeset = Person.changeset(%Person{}, %{given_name: "John", surname: "Doe"})
      assert get_field(changeset, :kind) == "family_member"
    end

    test "accepts acquaintance as kind" do
      changeset = Person.changeset(%Person{}, %{given_name: "John", surname: "Doe", kind: "acquaintance"})
      assert changeset.valid?
      assert get_field(changeset, :kind) == "acquaintance"
    end

    test "rejects invalid kind values" do
      changeset = Person.changeset(%Person{}, %{given_name: "John", surname: "Doe", kind: "stranger"})
      assert "is invalid" in errors_on(changeset).kind
    end
  end

  describe "acquaintance?/1" do
    test "returns true for acquaintance" do
      assert Person.acquaintance?(%Person{kind: "acquaintance"})
    end

    test "returns false for family_member" do
      refute Person.acquaintance?(%Person{kind: "family_member"})
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ancestry/people/person_kind_test.exs`
Expected: compilation errors — `kind` field doesn't exist, `acquaintance?/1` undefined

- [ ] **Step 3: Create migration**

Run: `mix ecto.gen.migration add_kind_to_persons`

Then edit the generated file:

```elixir
defmodule Ancestry.Repo.Migrations.AddKindToPersons do
  use Ecto.Migration

  def change do
    alter table(:persons) do
      add :kind, :string, null: false, default: "family_member"
    end
  end
end
```

- [ ] **Step 4: Update Person schema**

In `lib/ancestry/people/person.ex`:

Add field to schema (after `photo_status` line 25):
```elixir
field :kind, :string, default: "family_member"
```

Add `:kind` to `@cast_fields` list (line 36-54).

Add validation in `changeset/2` (after the `validate_inclusion(:gender, ...)` on line 60):
```elixir
|> validate_inclusion(:kind, ~w(family_member acquaintance))
```

Add helper function (after `display_name/1`):
```elixir
def acquaintance?(%__MODULE__{kind: "acquaintance"}), do: true
def acquaintance?(%__MODULE__{}), do: false
```

- [ ] **Step 5: Run migration and tests**

Run: `mix ecto.migrate && mix test test/ancestry/people/person_kind_test.exs`
Expected: all tests pass

- [ ] **Step 6: Commit**

```bash
git add priv/repo/migrations/*_add_kind_to_persons.exs lib/ancestry/people/person.ex test/ancestry/people/person_kind_test.exs
git commit -m "Add kind field to Person schema (family_member/acquaintance)"
```

---

### Task 2: People Context — Query Functions

Rename `list_people_for_family/1` to `list_people/1`, add `list_family_members/1`, filter search functions, and add conversion helpers.

**Files:**
- Modify: `lib/ancestry/people.ex`
- Modify: `test/support/factory.ex`
- Test: `test/ancestry/people_test.exs` (extend existing)

- [ ] **Step 1: Add acquaintance factory**

In `test/support/factory.ex`, add after `person_factory`:

```elixir
def acquaintance_factory do
  %Ancestry.People.Person{
    given_name: sequence(:given_name, &"Acquaintance #{&1}"),
    surname: "Test",
    kind: "acquaintance",
    organization: build(:organization)
  }
end
```

- [ ] **Step 2: Write failing tests for context functions**

Add to `test/ancestry/people_test.exs`:

```elixir
describe "list_people/1 and list_family_members/1" do
  setup do
    org = insert(:organization)
    family = insert(:family, organization: org)
    person = insert(:person, organization: org)
    acquaintance = insert(:acquaintance, organization: org)
    insert(:family_member, family: family, person: person)
    insert(:family_member, family: family, person: acquaintance)
    %{family: family, person: person, acquaintance: acquaintance}
  end

  test "list_people/1 returns both kinds", %{family: family, person: person, acquaintance: acquaintance} do
    people = People.list_people(family.id)
    ids = Enum.map(people, & &1.id)
    assert person.id in ids
    assert acquaintance.id in ids
  end

  test "list_family_members/1 returns only family_member kind", %{family: family, person: person, acquaintance: acquaintance} do
    people = People.list_family_members(family.id)
    ids = Enum.map(people, & &1.id)
    assert person.id in ids
    refute acquaintance.id in ids
  end
end

describe "search_family_members/3 excludes acquaintances" do
  setup do
    org = insert(:organization)
    family = insert(:family, organization: org)
    person = insert(:person, given_name: "Alice", organization: org)
    acquaintance = insert(:acquaintance, given_name: "Alicia", organization: org)
    insert(:family_member, family: family, person: person)
    insert(:family_member, family: family, person: acquaintance)
    %{family: family, person: person, acquaintance: acquaintance}
  end

  test "does not return acquaintances", %{family: family, person: person, acquaintance: acquaintance} do
    results = People.search_family_members("Al", family.id, 0)
    ids = Enum.map(results, & &1.id)
    assert person.id in ids
    refute acquaintance.id in ids
  end
end

describe "search_all_people/3 excludes acquaintances" do
  setup do
    org = insert(:organization)
    person = insert(:person, given_name: "Bob", organization: org)
    acquaintance = insert(:acquaintance, given_name: "Bobby", organization: org)
    %{org: org, person: person, acquaintance: acquaintance}
  end

  test "does not return acquaintances", %{org: org, person: person, acquaintance: acquaintance} do
    results = People.search_all_people("Bo", 0, org.id)
    ids = Enum.map(results, & &1.id)
    assert person.id in ids
    refute acquaintance.id in ids
  end
end

describe "set_default_member/2 blocks acquaintances" do
  setup do
    org = insert(:organization)
    family = insert(:family, organization: org)
    acquaintance = insert(:acquaintance, organization: org)
    insert(:family_member, family: family, person: acquaintance)
    %{family: family, acquaintance: acquaintance}
  end

  test "returns error for acquaintance", %{family: family, acquaintance: acquaintance} do
    assert {:error, :acquaintance_cannot_be_default} = People.set_default_member(family.id, acquaintance.id)
  end
end

describe "convert_to_acquaintance/1" do
  setup do
    org = insert(:organization)
    person = insert(:person, organization: org)
    %{person: person}
  end

  test "updates kind to acquaintance", %{person: person} do
    assert {:ok, updated} = People.convert_to_acquaintance(person)
    assert updated.kind == "acquaintance"
  end
end

describe "convert_to_family_member/1" do
  setup do
    org = insert(:organization)
    acquaintance = insert(:acquaintance, organization: org)
    %{acquaintance: acquaintance}
  end

  test "updates kind to family_member", %{acquaintance: acquaintance} do
    assert {:ok, updated} = People.convert_to_family_member(acquaintance)
    assert updated.kind == "family_member"
  end
end
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `mix test test/ancestry/people_test.exs`
Expected: FAIL — functions don't exist or return wrong results

- [ ] **Step 4: Implement context changes**

In `lib/ancestry/people.ex`:

**Rename** `list_people_for_family/1` (line 31) to `list_people/1`:
```elixir
def list_people(family_id) do
  Repo.all(
    from p in Person,
      join: fm in FamilyMember,
      on: fm.person_id == p.id,
      where: fm.family_id == ^family_id,
      order_by: [asc: p.surname, asc: p.given_name]
  )
end
```

**Add** `list_family_members/1` right after:
```elixir
def list_family_members(family_id) do
  Repo.all(
    from p in Person,
      join: fm in FamilyMember,
      on: fm.person_id == p.id,
      where: fm.family_id == ^family_id,
      where: p.kind == "family_member",
      order_by: [asc: p.surname, asc: p.given_name]
  )
end
```

**Filter `search_family_members/3`** (line 313): add `where: p.kind == "family_member"` to the query.

**Filter `search_all_people/2`** (line 258) and **`search_all_people/3`** (line 285): add `where: p.kind == "family_member"` to both queries.

**Guard `set_default_member/2`** (line 352): add a check at the top:
```elixir
def set_default_member(family_id, person_id) do
  person = Repo.get!(Person, person_id)

  if Person.acquaintance?(person) do
    {:error, :acquaintance_cannot_be_default}
  else
    Repo.transaction(fn ->
      Repo.update_all(
        from(fm in FamilyMember, where: fm.family_id == ^family_id),
        set: [is_default: false]
      )

      {1, _} =
        Repo.update_all(
          from(fm in FamilyMember,
            where: fm.family_id == ^family_id and fm.person_id == ^person_id
          ),
          set: [is_default: true]
        )
    end)
  end
end
```

**Add conversion functions** at the end of the module (before private helpers):

```elixir
def convert_to_acquaintance(%Person{} = person) do
  person
  |> Ecto.Changeset.change(%{kind: "acquaintance"})
  |> Repo.update()
end

def convert_to_family_member(%Person{} = person) do
  person
  |> Ecto.Changeset.change(%{kind: "family_member"})
  |> Repo.update()
end
```

**Scope `maybe_filter_unlinked/2`** (line 455) to family members only — add `where: p.kind == "family_member"` to the having clause or add a where clause:
```elixir
defp maybe_filter_unlinked(query, true) do
  query
  |> where([p], p.kind == "family_member")
  |> having(
    [rel: r, fm_other: fm_other],
    fragment(
      "COUNT(DISTINCT CASE WHEN ? IS NOT NULL THEN ? END) = 0",
      fm_other.id,
      r.id
    )
  )
end
```

**Scope `maybe_filter_no_family/2`** (line 134) to family members only:
```elixir
defp maybe_filter_no_family(query, true) do
  query
  |> where([p], p.kind == "family_member")
  |> join(:left, [p], fm in FamilyMember, on: fm.person_id == p.id, as: :fm_no_family)
  |> having([fm_no_family: fm], fragment("COUNT(DISTINCT ?) = 0", fm.family_id))
end
```

- [ ] **Step 5: Add factories to ExMachina**

In `test/support/factory.ex`, add a `family_member` factory (the join table record — **required** for tests in this plan):
```elixir
def family_member_factory do
  %Ancestry.People.FamilyMember{
    family: build(:family),
    person: build(:person)
  }
end
```

The `acquaintance_factory` was already added in Step 1.

- [ ] **Step 6: Fix ALL callers of the renamed function**

Search the entire codebase: `grep -r "list_people_for_family" lib/ test/`

Update every caller — here is the complete list:

| Caller | File | Change to | Reason |
|--------|------|-----------|--------|
| `FamilyGraph.for_family/1` | `lib/ancestry/people/family_graph.ex:23` | `People.list_family_members(family_id)` | Tree view — family members only |
| `KinshipLive.mount/3` | `lib/web/live/kinship_live.ex:19` | `People.list_family_members(family_id)` | Kinship — family members only |
| `FamilyLive.Show.mount/3` | `lib/web/live/family_live/show.ex:32` | `People.list_family_members(family_id)` | Tree view — family members only |
| `FamilyLive.Show.refresh_graph/1` | `lib/web/live/family_live/show.ex:720` | `People.list_family_members(family_id)` | Tree view — family members only |
| `FamilyLive.Print.mount/3` | `lib/web/live/family_live/print.ex:20` | `People.list_family_members(family_id)` | Print tree — family members only |
| `PersonLive.Index.mount/3` | `lib/web/live/person_live/index.ex:21` | `People.list_people(family_id)` | Sidebar — shows all kinds |
| Test assertions | `test/ancestry/families/create_family_from_person_test.exs` (9 call sites) | `People.list_people(family_id)` | Tests — all kinds |
| Test assertions | `test/ancestry/import/csv_test.exs` (2 call sites) | `People.list_people(family_id)` | Tests — all kinds |
| Any other callers found by grep | Decide per caller | `list_people` or `list_family_members` | Check context |

- [ ] **Step 7: Run all tests**

Run: `mix test`
Expected: all tests pass (no callers left using old name)

- [ ] **Step 8: Commit**

```bash
git add lib/ancestry/people.ex lib/ancestry/people/family_graph.ex lib/web/live/kinship_live.ex test/ancestry/people_test.exs test/support/factory.ex
git commit -m "Add list_people/list_family_members, filter acquaintances from search/defaults"
```

---

### Task 3: Relationship Guard

Block relationship creation for acquaintances.

**Files:**
- Modify: `lib/ancestry/relationships.ex:9-23`
- Test: `test/ancestry/relationships_test.exs` (extend existing)

- [ ] **Step 1: Write failing test**

Add to `test/ancestry/relationships_test.exs`:

```elixir
describe "create_relationship/4 acquaintance guard" do
  setup do
    org = insert(:organization)
    person = insert(:person, organization: org)
    acquaintance = insert(:acquaintance, organization: org)
    %{person: person, acquaintance: acquaintance}
  end

  test "blocks when person_a is acquaintance", %{person: person, acquaintance: acquaintance} do
    assert {:error, :acquaintance_cannot_have_relationships} =
             Relationships.create_relationship(acquaintance, person, "parent")
  end

  test "blocks when person_b is acquaintance", %{person: person, acquaintance: acquaintance} do
    assert {:error, :acquaintance_cannot_have_relationships} =
             Relationships.create_relationship(person, acquaintance, "parent")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/ancestry/relationships_test.exs --only "acquaintance guard"`
Expected: FAIL — no guard exists, relationship gets created

- [ ] **Step 3: Add guard to `create_relationship/4`**

In `lib/ancestry/relationships.ex`, update `create_relationship/4` (line 9):

```elixir
def create_relationship(person_a, person_b, type, metadata_attrs \\ %{}) do
  attrs = %{
    person_a_id: person_a.id,
    person_b_id: person_b.id,
    type: type,
    metadata: Map.put(metadata_attrs, :__type__, type)
  }

  with :ok <- validate_not_acquaintance(person_a, person_b),
       :ok <- validate_parent_limit(person_b.id, type),
       :ok <- validate_unique_partner_pair(person_a.id, person_b.id, type) do
    %Relationship{}
    |> Relationship.changeset(attrs)
    |> Repo.insert()
  end
end
```

Add the validation function (near other `validate_*` private functions):

```elixir
defp validate_not_acquaintance(person_a, person_b) do
  if Person.acquaintance?(person_a) or Person.acquaintance?(person_b) do
    {:error, :acquaintance_cannot_have_relationships}
  else
    :ok
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/ancestry/relationships_test.exs`
Expected: all tests pass

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/relationships.ex test/ancestry/relationships_test.exs
git commit -m "Block relationship creation for acquaintance persons"
```

---

### Task 4: Person Form — Acquaintance Checkbox

Add a checkbox to the person creation/edit form.

**Files:**
- Modify: `lib/web/live/shared/person_form_component.html.heex:217-232`

- [ ] **Step 1: Add the acquaintance checkbox**

In `lib/web/live/shared/person_form_component.html.heex`, after the "Living" checkbox block (line 232, after the closing `</div>` of the living checkbox), add:

```heex
    <%!-- Acquaintance checkbox --%>
    <div class="md:grid md:grid-cols-[10rem_1fr] md:gap-x-4 md:items-center">
      <div></div>
      <label class="flex items-center gap-2 cursor-pointer" {test_id("person-acquaintance-label")}>
        <input type="hidden" name="person[kind]" value="family_member" />
        <input
          type="checkbox"
          name="person[kind]"
          id="person-kind"
          value="acquaintance"
          checked={to_string(@form[:kind].value) == "acquaintance"}
          class="w-4 h-4 accent-ds-primary rounded"
          {test_id("person-acquaintance-checkbox")}
        />
        <span class="text-sm text-ds-on-surface">{gettext("This person is not a family member (acquaintance)")}</span>
      </label>
    </div>
```

- [ ] **Step 2: Verify the form works**

Start dev server: `iex -S mix phx.server`
Navigate to a family → Add member → verify checkbox appears, unchecked by default.
Check the checkbox → submit → verify person is created with `kind: "acquaintance"`.

- [ ] **Step 3: Commit**

```bash
git add lib/web/live/shared/person_form_component.html.heex
git commit -m "Add acquaintance checkbox to person form"
```

---

### Task 5: People Lists — Badge and Filter

Add "Non-family" badge and "Non-family only" filter to both people list pages.

**Files:**
- Modify: `lib/web/live/people_live/index.ex`
- Modify: `lib/web/live/people_live/index.html.heex`
- Modify: `lib/web/live/org_people_live/index.ex`
- Modify: `lib/web/live/org_people_live/index.html.heex`

- [ ] **Step 1: Add `acquaintance_only` assign and filter to `PeopleLive.Index`**

In `lib/web/live/people_live/index.ex`:

Add `:acquaintance_only` assign in `mount/3` (after `:unlinked_only`):
```elixir
|> assign(:acquaintance_only, false)
```

Add a new event handler:
```elixir
def handle_event("toggle_acquaintance", _, socket) do
  acquaintance_only = !socket.assigns.acquaintance_only
  people = refetch_people(socket, acquaintance_only: acquaintance_only)

  {:noreply,
   socket
   |> assign(:acquaintance_only, acquaintance_only)
   |> assign(:selected, MapSet.new())
   |> assign(:people_empty?, people == [])
   |> stream(:people, people, reset: true)}
end
```

Update `refetch_people/2` to pass the new option:
```elixir
defp refetch_people(socket, opts \\ []) do
  unlinked_only = Keyword.get(opts, :unlinked_only, socket.assigns.unlinked_only)
  acquaintance_only = Keyword.get(opts, :acquaintance_only, socket.assigns.acquaintance_only)

  People.list_people_for_family_with_relationship_counts(
    socket.assigns.family.id,
    socket.assigns.filter,
    unlinked_only: unlinked_only,
    acquaintance_only: acquaintance_only
  )
end
```

Update the "filter" event handler to pass `acquaintance_only`:
```elixir
def handle_event("filter", %{"filter" => query}, socket) do
  family_id = socket.assigns.family.id

  people =
    People.list_people_for_family_with_relationship_counts(family_id, query,
      unlinked_only: socket.assigns.unlinked_only,
      acquaintance_only: socket.assigns.acquaintance_only
    )
  ...
end
```

- [ ] **Step 2: Add acquaintance_only filter to `People` context**

In `lib/ancestry/people.ex`, update `list_people_for_family_with_relationship_counts` overloads to accept and pass through `:acquaintance_only` option:

Add a private helper:
```elixir
defp maybe_filter_acquaintance_only(query, true) do
  where(query, [p], p.kind == "acquaintance")
end

defp maybe_filter_acquaintance_only(query, false), do: query
```

Pipe it in the relevant function clauses (after `maybe_filter_unlinked`):
```elixir
|> maybe_filter_unlinked(unlinked_only)
|> maybe_filter_acquaintance_only(acquaintance_only)
```

Do the same for `list_people_for_org` overloads.

- [ ] **Step 3: Add "Non-family" filter chip to people_live/index.html.heex**

In `lib/web/live/people_live/index.html.heex`, after the "Unlinked" button (around line 103), add:

```heex
    <button
      phx-click="toggle_acquaintance"
      class={[
        "inline-flex items-center gap-1.5 rounded-ds-sharp px-3 py-1.5 text-sm font-ds-body font-semibold",
        if(@acquaintance_only,
          do: "bg-ds-tertiary text-ds-on-surface",
          else:
            "bg-ds-surface-high text-ds-on-surface hover:bg-ds-surface-highest transition-colors"
        )
      ]}
      {test_id("people-acquaintance-chip")}
    >
      <.icon name="hero-user-minus-mini" class="w-4 h-4" /> {gettext("Non-family")}
    </button>
```

- [ ] **Step 4: Add "Non-family" badge to person rows**

In `lib/web/live/people_live/index.html.heex`, in the Name cell (around line 224-238), after the person name, add:

```heex
<%= if person.kind == "acquaintance" do %>
  <span class="ml-1.5 inline-flex items-center px-1.5 py-0.5 rounded-full text-[10px] font-semibold bg-ds-surface-high text-ds-on-surface-variant">
    {gettext("Non-family")}
  </span>
<% end %>
```

- [ ] **Step 5: Repeat for OrgPeopleLive.Index**

Apply the same changes to `lib/web/live/org_people_live/index.ex` and `lib/web/live/org_people_live/index.html.heex`:
- Add `:acquaintance_only` assign
- Add `toggle_acquaintance` event
- Update `refetch_people/2`
- Update filter event
- Add "Non-family" chip and badge to template

- [ ] **Step 6: Run tests and verify in browser**

Run: `mix test`
Start dev server and verify filter chips and badges work.

- [ ] **Step 7: Commit**

```bash
git add lib/ancestry/people.ex lib/web/live/people_live/index.ex lib/web/live/people_live/index.html.heex lib/web/live/org_people_live/index.ex lib/web/live/org_people_live/index.html.heex
git commit -m "Add Non-family badge and filter to people lists"
```

---

### Task 6: Person Show — Hide Relationships + Conversion Actions

Conditionally hide the relationships section for acquaintances and add conversion UI.

**Files:**
- Modify: `lib/web/live/person_live/show.ex`
- Modify: `lib/web/live/person_live/show.html.heex`

- [ ] **Step 1: Skip relationship loading for acquaintances**

In `lib/web/live/person_live/show.ex`, update `load_relationships/2` (line 383) to check kind:

```elixir
defp load_relationships(socket, person) do
  if Person.acquaintance?(person) do
    socket
    |> assign(:parents, [])
    |> assign(:parents_marriage, nil)
    |> assign(:partner_children, [])
    |> assign(:coparent_children, [])
    |> assign(:siblings, [])
    |> assign(:solo_children, [])
    |> assign(:adding_relationship, nil)
    |> assign(:adding_partner_id, nil)
    |> assign_new(:add_rel_key, fn -> 0 end)
    |> assign(:editing_relationship, nil)
    |> assign(:edit_relationship_form, nil)
  else
    # ... existing code ...
  end
end
```

- [ ] **Step 2: Add `count_relationships/1` to Relationships context**

In `lib/ancestry/relationships.ex`, add:

```elixir
def count_relationships(person_id) do
  Repo.one(
    from r in Relationship,
      where: r.person_a_id == ^person_id or r.person_b_id == ^person_id,
      select: count(r.id)
  )
end
```

- [ ] **Step 3: Update `convert_to_acquaintance/1` in People context to use Ecto.Multi**

In `lib/ancestry/people.ex`, replace the simple `convert_to_acquaintance/1` with a transactional version that also clears default member status:

```elixir
def convert_to_acquaintance(%Person{} = person) do
  alias Ecto.Multi

  person = Repo.preload(person, :families)

  Multi.new()
  |> Multi.update(:person, Ecto.Changeset.change(person, %{kind: "acquaintance"}))
  |> Multi.run(:clear_defaults, fn repo, _changes ->
    for family <- person.families do
      repo.update_all(
        from(fm in FamilyMember,
          where: fm.family_id == ^family.id and fm.person_id == ^person.id and fm.is_default == true
        ),
        set: [is_default: false]
      )
    end
    {:ok, :cleared}
  end)
  |> Repo.transaction()
  |> case do
    {:ok, %{person: person}} -> {:ok, person}
    {:error, _op, changeset, _} -> {:error, changeset}
  end
end
```

- [ ] **Step 4: Add conversion event handlers to LiveView**

In `lib/web/live/person_live/show.ex`, add event handlers:

```elixir
def handle_event("convert_to_family_member", _, socket) do
  case People.convert_to_family_member(socket.assigns.person) do
    {:ok, person} ->
      {:noreply,
       socket
       |> assign(:person, person)
       |> load_relationships(person)
       |> put_flash(:info, gettext("Converted to family member"))}

    {:error, _} ->
      {:noreply, put_flash(socket, :error, gettext("Failed to convert"))}
  end
end

def handle_event("convert_to_acquaintance", _, socket) do
  person = socket.assigns.person
  relationship_count = Relationships.count_relationships(person.id)

  if relationship_count > 0 do
    {:noreply, put_flash(socket, :error, gettext("Remove all relationships before converting"))}
  else
    case People.convert_to_acquaintance(person) do
      {:ok, person} ->
        {:noreply,
         socket
         |> assign(:person, person)
         |> load_relationships(person)
         |> put_flash(:info, gettext("Converted to non-family"))}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, gettext("Failed to convert"))}
    end
  end
end
```

- [ ] **Step 4: Wrap relationships section in kind check in template**

In `lib/web/live/person_live/show.html.heex`, wrap the relationships section (line 272-568) with:

```heex
<%= unless Ancestry.People.Person.acquaintance?(@person) do %>
  <%!-- Existing relationships section --%>
  ...
<% end %>
```

- [ ] **Step 5: Add "Convert to family member" banner for acquaintances**

In `lib/web/live/person_live/show.html.heex`, before the relationships section (or where it would be), add:

```heex
<%= if Ancestry.People.Person.acquaintance?(@person) do %>
  <div class="px-4 py-4 sm:px-6 lg:px-8 max-w-4xl mx-auto">
    <div
      class="flex items-center justify-between rounded-ds-sharp bg-ds-tertiary/10 border border-ds-tertiary/20 p-4"
      {test_id("convert-to-family-banner")}
    >
      <div class="flex items-center gap-3">
        <.icon name="hero-user-plus" class="w-5 h-5 text-ds-tertiary" />
        <p class="text-sm text-ds-on-surface">
          {gettext("This person is not a family member.")}
        </p>
      </div>
      <button
        phx-click="convert_to_family_member"
        class="px-4 py-1.5 rounded-ds-sharp bg-ds-primary text-ds-on-primary text-sm font-semibold hover:opacity-90 transition-opacity"
        {test_id("convert-to-family-btn")}
      >
        {gettext("Convert to family member")}
      </button>
    </div>
  </div>
<% end %>
```

- [ ] **Step 6: Add "Convert to non-family" to the toolbar dropdown**

In `lib/web/live/person_live/show.html.heex`, in the desktop actions section (line 55-87), add a "more actions" dropdown or a new button for family members. For family members only:

```heex
<%= unless Ancestry.People.Person.acquaintance?(@person) do %>
  <button
    type="button"
    id="convert-to-acquaintance-btn"
    phx-click="convert_to_acquaintance"
    data-confirm={gettext("Convert this person to non-family? They will be excluded from the tree view and relationships.")}
    class="p-2 text-ds-on-surface-variant hover:text-ds-on-surface"
    aria-label={gettext("Convert to non-family")}
    {test_id("convert-to-acquaintance-btn")}
  >
    <.icon name="hero-user-minus" class="size-5" />
  </button>
<% end %>
```

Add the same to the mobile nav drawer actions.

- [ ] **Step 7: Run tests and verify in browser**

Run: `mix test`
Start dev server and test both conversion flows.

- [ ] **Step 8: Commit**

```bash
git add lib/ancestry/people.ex lib/ancestry/relationships.ex lib/web/live/person_live/show.ex lib/web/live/person_live/show.html.heex
git commit -m "Add conversion flows and hide relationships for acquaintances"
```

---

### Task 7: Tree View + Kinship + Print — Verify `list_family_members` callers

All tree-related callers should have been updated in Task 2 Step 6. This task verifies completeness.

**Files:**
- Verify: `lib/ancestry/people/family_graph.ex:23` → `People.list_family_members(family_id)`
- Verify: `lib/web/live/kinship_live.ex:19` → `People.list_family_members(family_id)`
- Verify: `lib/web/live/family_live/show.ex:32,720` → `People.list_family_members(family_id)`
- Verify: `lib/web/live/family_live/print.ex:20` → `People.list_family_members(family_id)`
- Verify: `lib/web/live/person_live/index.ex:21` → `People.list_people(family_id)`

- [ ] **Step 1: Verify no remaining `list_people_for_family` calls**

Run: `grep -r "list_people_for_family" lib/ test/`
Expected: zero results

- [ ] **Step 2: Verify birthday calendar needs no changes**

`list_birthdays_for_family/1` in `lib/ancestry/people.ex:9` joins on `FamilyMember` with no kind filter — it already returns all kinds, which is correct per the spec (acquaintances appear in birthday calendar).

No code change needed, but add a test in Task 9 to confirm acquaintance birthdays appear.

- [ ] **Step 3: Run tests**

Run: `mix test`
Expected: all tests pass

- [ ] **Step 4: Commit** (if any files needed fixing)

```bash
git add -A
git commit -m "Verify all list_people_for_family callers updated"
```

---

### Task 8: i18n — Extract and Translate

Extract gettext strings and add Spanish translations.

**Files:**
- Modify: `priv/gettext/es-UY/LC_MESSAGES/default.po`

- [ ] **Step 1: Extract gettext strings**

Run: `mix gettext.extract --merge`

- [ ] **Step 2: Add Spanish translations**

In `priv/gettext/es-UY/LC_MESSAGES/default.po`, find and translate the new entries:

| English | Spanish |
|---------|---------|
| "This person is not a family member (acquaintance)" | "Esta persona no es familiar (conocido/a)" |
| "Non-family" | "No familiar" |
| "Convert to family member" | "Convertir en familiar" |
| "Convert to non-family" | "Convertir en no familiar" |
| "This person is not a family member." | "Esta persona no es familiar." |
| "Converted to family member" | "Convertido/a en familiar" |
| "Converted to non-family" | "Convertido/a en no familiar" |
| "Failed to convert" | "Error al convertir" |
| "Remove all relationships before converting" | "Elimine todas las relaciones antes de convertir" |
| "Convert this person to non-family? They will be excluded from the tree view and relationships." | "Convertir esta persona en no familiar? Será excluida del árbol genealógico y las relaciones." |

- [ ] **Step 3: Commit**

```bash
git add priv/gettext/
git commit -m "Add Spanish translations for acquaintance person feature"
```

---

### Task 9: E2E Tests

Write end-to-end tests covering the acquaintance person user flows.

**Files:**
- Create: `test/user_flows/acquaintance_person_test.exs`

- [ ] **Step 1: Write test file**

Create `test/user_flows/acquaintance_person_test.exs` using `Web.ConnCase` with `Phoenix.LiveViewTest` (LiveView tests, not Playwright E2E — this feature doesn't depend on JS):

```elixir
defmodule Web.UserFlows.AcquaintancePersonTest do
  use Web.ConnCase, async: true
  import Phoenix.LiveViewTest
  import Ancestry.Factory

  # Creating an acquaintance person
  #
  # Given an existing family
  # When the user navigates to add a new member
  # And checks "This person is not a family member (acquaintance)"
  # And fills in given name and surname
  # And clicks Create
  # Then the person is created with kind "acquaintance"
  # And the person appears in the people list with a "Non-family" badge
  #
  # Converting acquaintance to family member
  #
  # Given an acquaintance person
  # When the user views the acquaintance's show page
  # Then a "Convert to family member" banner is shown
  # And the relationships section is hidden
  #
  # When the user clicks "Convert to family member"
  # Then the person is converted
  # And the relationships section appears
  # And the banner disappears
  #
  # Converting family member to acquaintance
  #
  # Given a family member with no relationships
  # When the user clicks "Convert to non-family" on their show page
  # Then the person is converted to acquaintance
  # And the relationships section disappears
  # And the "Convert to family member" banner appears
  #
  # Blocking conversion when relationships exist
  #
  # Given a family member with relationships
  # When the user clicks "Convert to non-family"
  # Then a warning is shown: "Remove all relationships before converting"
  # And the person remains a family member
  #
  # Non-family filter on people list
  #
  # Given a family with both family members and acquaintances
  # When the user clicks "Non-family" filter chip
  # Then only acquaintances are shown

  setup %{conn: conn} do
    account = insert(:account)
    org = insert(:organization)
    insert(:account_organization, account: account, organization: org)
    family = insert(:family, organization: org)
    conn = log_in_account(conn, account)

    %{conn: conn, org: org, family: family, account: account}
  end

  describe "creating acquaintance" do
    test "creates person with acquaintance kind via checkbox", %{conn: conn, org: org, family: family} do
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}/members/new")

      view
      |> form("#person-form", person: %{given_name: "Neighbor", surname: "Joe", kind: "acquaintance"})
      |> render_submit()

      # Verify person was created as acquaintance in the people list
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}/people")
      html = render(view)
      assert html =~ "Neighbor"
      assert html =~ "Non-family"
    end
  end

  describe "person show page for acquaintance" do
    setup %{org: org, family: family} do
      acquaintance = insert(:acquaintance, given_name: "Friend", surname: "Smith", organization: org)
      insert(:family_member, family: family, person: acquaintance)
      %{acquaintance: acquaintance}
    end

    test "hides relationships section and shows convert banner", %{conn: conn, org: org, acquaintance: acquaintance} do
      {:ok, _view, html} = live(conn, ~p"/org/#{org.id}/people/#{acquaintance.id}")

      assert html =~ "Convert to family member"
      refute html =~ "Relationships"
    end

    test "converts acquaintance to family member", %{conn: conn, org: org, acquaintance: acquaintance} do
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/people/#{acquaintance.id}")

      view |> element(test_id("convert-to-family-btn")) |> render_click()

      html = render(view)
      # Banner should disappear, relationships section should appear
      refute html =~ "Convert to family member"
      assert html =~ "Relationships"
    end
  end

  describe "person show page for family member" do
    setup %{org: org, family: family} do
      person = insert(:person, given_name: "Regular", surname: "Member", organization: org)
      insert(:family_member, family: family, person: person)
      %{person: person}
    end

    test "shows convert to non-family button", %{conn: conn, org: org, family: family, person: person} do
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

      assert has_element?(view, test_id("convert-to-acquaintance-btn"))
    end

    test "converts family member to acquaintance when no relationships", %{conn: conn, org: org, family: family, person: person} do
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

      view |> element(test_id("convert-to-acquaintance-btn")) |> render_click()

      html = render(view)
      assert html =~ "Convert to family member"
      refute html =~ "Relationships"
    end

    test "blocks conversion when relationships exist", %{conn: conn, org: org, family: family, person: person} do
      other = insert(:person, given_name: "Other", surname: "Person", organization: org)
      insert(:family_member, family: family, person: other)
      Ancestry.Relationships.create_relationship(person, other, "parent", %{role: "father"})

      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/people/#{person.id}?from_family=#{family.id}")

      view |> element(test_id("convert-to-acquaintance-btn")) |> render_click()

      # Should still be a family member with flash error
      assert render(view) =~ "Remove all relationships"
    end
  end

  describe "people list filters" do
    setup %{org: org, family: family} do
      person = insert(:person, given_name: "Family", surname: "Person", organization: org)
      acquaintance = insert(:acquaintance, given_name: "NonFamily", surname: "Person", organization: org)
      insert(:family_member, family: family, person: person)
      insert(:family_member, family: family, person: acquaintance)
      %{person: person, acquaintance: acquaintance}
    end

    test "non-family filter shows only acquaintances", %{conn: conn, org: org, family: family} do
      {:ok, view, _html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}/people")

      # Both should be visible initially
      html = render(view)
      assert html =~ "Family"
      assert html =~ "NonFamily"

      # Toggle acquaintance filter
      view |> element(test_id("people-acquaintance-chip")) |> render_click()

      html = render(view)
      assert html =~ "NonFamily"
      # Family members should be filtered out
      refute html =~ ">Family Person<"
    end

    test "non-family badge appears next to acquaintance name", %{conn: conn, org: org, family: family} do
      {:ok, _view, html} = live(conn, ~p"/org/#{org.id}/families/#{family.id}/people")

      assert html =~ "Non-family"
    end
  end
end
```

- [ ] **Step 2: Run tests**

Run: `mix test test/user_flows/acquaintance_person_test.exs`
Expected: all tests pass

- [ ] **Step 4: Commit**

```bash
git add test/user_flows/acquaintance_person_test.exs
git commit -m "Add E2E tests for acquaintance person feature"
```

---

### Task 10: Precommit Check

Run the full precommit suite to catch any issues.

- [ ] **Step 1: Run precommit**

Run: `mix precommit`

This runs: compile (warnings-as-errors), remove unused deps, format, and tests.

- [ ] **Step 2: Fix any issues**

Address compilation warnings, formatting issues, or test failures.

- [ ] **Step 3: Final commit if needed**

```bash
git add -A
git commit -m "Fix precommit issues for acquaintance person feature"
```
