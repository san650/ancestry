# Diacritics-Insensitive Person Search — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make all person search surfaces find people regardless of diacritics (e.g., "maria" finds "María").

**Architecture:** Enable PostgreSQL `unaccent` extension, wrap existing `ILIKE` queries with `unaccent()`, and add Elixir-side Unicode normalization for client-side filtering in LiveView components.

**Tech Stack:** PostgreSQL `unaccent` extension, Elixir `String.normalize/2`, Ecto fragments

---

### Task 1: Create the `unaccent` extension migration

**Files:**
- Create: `priv/repo/migrations/YYYYMMDDHHMMSS_enable_unaccent.exs` (use `mix ecto.gen.migration`)

**Step 1: Generate migration**

Run: `mix ecto.gen.migration enable_unaccent`

**Step 2: Write the migration**

```elixir
defmodule Ancestry.Repo.Migrations.EnableUnaccent do
  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS unaccent"
  end

  def down do
    execute "DROP EXTENSION IF EXISTS unaccent"
  end
end
```

**Step 3: Run migration**

Run: `mix ecto.migrate`
Expected: Migration runs successfully.

**Step 4: Commit**

```bash
git add priv/repo/migrations/*enable_unaccent*
git commit -m "feat: enable PostgreSQL unaccent extension"
```

---

### Task 2: Create `Ancestry.StringUtils` module with `normalize/1`

**Files:**
- Create: `lib/ancestry/string_utils.ex`
- Test: `test/ancestry/string_utils_test.exs`

**Step 1: Write the failing test**

```elixir
defmodule Ancestry.StringUtilsTest do
  use ExUnit.Case, async: true

  alias Ancestry.StringUtils

  describe "normalize/1" do
    test "strips diacritics and lowercases" do
      assert StringUtils.normalize("María") == "maria"
      assert StringUtils.normalize("José") == "jose"
      assert StringUtils.normalize("González") == "gonzalez"
    end

    test "handles plain ASCII" do
      assert StringUtils.normalize("John") == "john"
    end

    test "handles nil" do
      assert StringUtils.normalize(nil) == ""
    end

    test "handles empty string" do
      assert StringUtils.normalize("") == ""
    end

    test "handles multiple diacritics" do
      assert StringUtils.normalize("Ñoño") == "nono"
    end

    test "handles umlauts and other marks" do
      assert StringUtils.normalize("Müller") == "muller"
      assert StringUtils.normalize("Björk") == "bjork"
      assert StringUtils.normalize("François") == "francois"
    end
  end
end
```

**Step 2: Run test to verify it fails**

Run: `mix test test/ancestry/string_utils_test.exs`
Expected: FAIL — module `Ancestry.StringUtils` not found.

**Step 3: Write minimal implementation**

```elixir
defmodule Ancestry.StringUtils do
  @doc """
  Strips diacritics and lowercases the string for accent-insensitive comparison.
  """
  def normalize(nil), do: ""
  def normalize(""), do: ""

  def normalize(string) do
    string
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
  end
end
```

**Step 4: Run test to verify it passes**

Run: `mix test test/ancestry/string_utils_test.exs`
Expected: All tests PASS.

**Step 5: Commit**

```bash
git add lib/ancestry/string_utils.ex test/ancestry/string_utils_test.exs
git commit -m "feat: add StringUtils.normalize/1 for diacritics stripping"
```

---

### Task 3: Update database search queries in `Ancestry.People`

**Files:**
- Modify: `lib/ancestry/people.ex:64-168` (all 4 search functions)
- Test: `test/ancestry/people_test.exs`

**Step 1: Write the failing tests**

Add to `test/ancestry/people_test.exs` inside the existing `describe "search_people/2"` block:

```elixir
test "finds people with diacritics using unaccented search" do
  family = family_fixture()
  other_family = family_fixture(%{name: "Other Family"})

  {:ok, _} = People.create_person(other_family, %{given_name: "María", surname: "González"})

  results = People.search_people("maria", family.id)
  assert length(results) == 1
  assert hd(results).given_name == "María"

  results = People.search_people("gonzalez", family.id)
  assert length(results) == 1
  assert hd(results).surname == "González"
end

test "finds people without diacritics using accented search" do
  family = family_fixture()
  other_family = family_fixture(%{name: "Other Family"})

  {:ok, _} = People.create_person(other_family, %{given_name: "Maria", surname: "Gonzalez"})

  results = People.search_people("María", family.id)
  assert length(results) == 1

  results = People.search_people("González", family.id)
  assert length(results) == 1
end
```

Add a new `describe` block for `search_all_people`:

```elixir
describe "search_all_people/1 diacritics" do
  test "finds people with diacritics using unaccented search" do
    family = family_fixture()
    {:ok, _} = People.create_person(family, %{given_name: "José", surname: "García"})

    results = People.search_all_people("jose")
    assert length(results) == 1
    assert hd(results).given_name == "José"
  end
end
```

Add to the existing `describe "search_family_members/3"` block:

```elixir
test "finds family members with diacritics using unaccented search" do
  family = family_fixture()
  {:ok, maria} = People.create_person(family, %{given_name: "María", surname: "López"})
  {:ok, jose} = People.create_person(family, %{given_name: "José", surname: "López"})

  results = People.search_family_members("maria", family.id, jose.id)
  assert length(results) == 1
  assert hd(results).id == maria.id
end
```

**Step 2: Run tests to verify they fail**

Run: `mix test test/ancestry/people_test.exs`
Expected: The new diacritics tests FAIL (existing tests still pass).

**Step 3: Update all 4 search functions**

In `lib/ancestry/people.ex`, replace each `ilike` clause with the `unaccent` fragment. Apply to all 4 functions: `search_people/2`, `search_all_people/1`, `search_all_people/2`, `search_family_members/3`.

Replace this pattern (appears in each function):

```elixir
ilike(p.given_name, ^like) or
  ilike(p.surname, ^like) or
  ilike(p.nickname, ^like)
```

With:

```elixir
fragment("unaccent(?) ILIKE unaccent(?)", p.given_name, ^like) or
  fragment("unaccent(?) ILIKE unaccent(?)", p.surname, ^like) or
  fragment("unaccent(?) ILIKE unaccent(?)", p.nickname, ^like)
```

And in the 3 functions that have the `alternate_names` fragment, replace:

```elixir
fragment(
  "EXISTS (SELECT 1 FROM unnest(?) AS name WHERE name ILIKE ?)",
  p.alternate_names,
  ^like
)
```

With:

```elixir
fragment(
  "EXISTS (SELECT 1 FROM unnest(?) AS name WHERE unaccent(name) ILIKE unaccent(?))",
  p.alternate_names,
  ^like
)
```

**Step 4: Run tests to verify they pass**

Run: `mix test test/ancestry/people_test.exs`
Expected: All tests PASS (both old and new).

**Step 5: Commit**

```bash
git add lib/ancestry/people.ex test/ancestry/people_test.exs
git commit -m "feat: add diacritics-insensitive search to People queries"
```

---

### Task 4: Update client-side filtering in `PersonSelectorComponent`

**Files:**
- Modify: `lib/web/live/family_live/person_selector_component.ex:111-126` (`assign_filtered/1`)

**Step 1: Update the filter logic**

In `assign_filtered/1`, replace:

```elixir
defp assign_filtered(socket) do
  query = String.downcase(String.trim(socket.assigns.query))
  people = socket.assigns.people

  filtered =
    if query == "" do
      people
    else
      Enum.filter(people, fn person ->
        name = String.downcase(Person.display_name(person))
        String.contains?(name, query)
      end)
    end

  assign(socket, :filtered_people, filtered)
end
```

With:

```elixir
defp assign_filtered(socket) do
  query = Ancestry.StringUtils.normalize(String.trim(socket.assigns.query))
  people = socket.assigns.people

  filtered =
    if query == "" do
      people
    else
      Enum.filter(people, fn person ->
        name = Ancestry.StringUtils.normalize(Person.display_name(person))
        String.contains?(name, query)
      end)
    end

  assign(socket, :filtered_people, filtered)
end
```

**Step 2: Run full test suite to verify no regressions**

Run: `mix test`
Expected: All tests PASS.

**Step 3: Commit**

```bash
git add lib/web/live/family_live/person_selector_component.ex
git commit -m "feat: diacritics-insensitive filtering in PersonSelectorComponent"
```

---

### Task 5: Update client-side filtering in `KinshipLive`

**Files:**
- Modify: `lib/web/live/kinship_live.ex:161-175` (`filter_people/3`)

**Step 1: Update the filter logic**

Replace:

```elixir
defp filter_people(people, query, exclude_person) do
  exclude_id = if exclude_person, do: exclude_person.id, else: nil
  query_down = String.downcase(String.trim(query))

  people
  |> Enum.reject(&(&1.id == exclude_id))
  |> Enum.filter(fn person ->
    if query_down == "" do
      true
    else
      name = String.downcase(Person.display_name(person))
      String.contains?(name, query_down)
    end
  end)
end
```

With:

```elixir
defp filter_people(people, query, exclude_person) do
  exclude_id = if exclude_person, do: exclude_person.id, else: nil
  query_normalized = Ancestry.StringUtils.normalize(String.trim(query))

  people
  |> Enum.reject(&(&1.id == exclude_id))
  |> Enum.filter(fn person ->
    if query_normalized == "" do
      true
    else
      name = Ancestry.StringUtils.normalize(Person.display_name(person))
      String.contains?(name, query_normalized)
    end
  end)
end
```

**Step 2: Run full test suite to verify no regressions**

Run: `mix test`
Expected: All tests PASS.

**Step 3: Commit**

```bash
git add lib/web/live/kinship_live.ex
git commit -m "feat: diacritics-insensitive filtering in KinshipLive"
```

---

### Task 6: Run precommit checks

**Step 1: Run precommit**

Run: `mix precommit`
Expected: Compilation (warnings-as-errors), formatting, and all tests pass.

**Step 2: Fix any issues found, commit fixes**
