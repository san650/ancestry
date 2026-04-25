# People Search Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix people search so cross-field queries ("martin v" for "Martín Vazquez") and diacritics in @mention ("@martí") work correctly everywhere.

**Architecture:** Add a denormalized `name_search` column to `persons` computed in the changeset from all name fields (normalized: no diacritics, downcased). All 6 SQL search functions switch from multi-field `unaccent()` fragments to a single `ilike` on `name_search`. JS regex in Trix @mention updated to accept Unicode.

**Tech Stack:** Elixir, Ecto, PostgreSQL, Phoenix LiveView, JavaScript (Trix editor)

**Spec:** `docs/plans/2026-04-25-people-search-fix-design.md`

---

## File Map

**Create:**
- `priv/repo/migrations/TIMESTAMP_add_name_search_to_persons.exs` — migration + Elixir backfill

**Modify:**
- `lib/ancestry/string_utils.ex` — add `normalize(nil)` clause and `normalize_sql_search/1`
- `lib/ancestry/people/person.ex:58-71` — add `name_search` field, compute in changeset
- `lib/ancestry/people.ex:74-96,119-141,247-357` — simplify all 6 search functions to use `ilike(p.name_search, ^like)`
- `assets/js/trix_editor.js:114` — fix regex to accept Unicode characters
- `test/ancestry/people_test.exs` — add tests for name_search computation and cross-field search
- `test/ancestry/string_utils_test.exs` — add tests for `normalize(nil)` and `normalize_sql_search/1`

---

### Task 1: StringUtils — nil clause + normalize_sql_search

Add `normalize(nil)` and `normalize_sql_search/1` to StringUtils.

**Files:**
- Modify: `lib/ancestry/string_utils.ex`
- Test: `test/ancestry/string_utils_test.exs`

- [ ] **Step 1: Write failing tests**

Check if `test/ancestry/string_utils_test.exs` exists. If not, create it:

```elixir
defmodule Ancestry.StringUtilsTest do
  use ExUnit.Case, async: true

  alias Ancestry.StringUtils

  describe "normalize/1" do
    test "returns empty string for nil" do
      assert StringUtils.normalize(nil) == ""
    end

    test "strips diacritics and lowercases" do
      assert StringUtils.normalize("Martín") == "martin"
    end

    test "returns empty string for empty string" do
      assert StringUtils.normalize("") == ""
    end
  end

  describe "normalize_sql_search/1" do
    test "normalizes, escapes, and wraps in wildcards" do
      assert StringUtils.normalize_sql_search("Martín") == "%martin%"
    end

    test "escapes SQL wildcards" do
      assert StringUtils.normalize_sql_search("100%") == "%100\\%%"
    end

    test "escapes underscores" do
      assert StringUtils.normalize_sql_search("a_b") == "%a\\_b%"
    end

    test "escapes backslashes" do
      assert StringUtils.normalize_sql_search("a\\b") == "%a\\\\b%"
    end

    test "handles nil" do
      assert StringUtils.normalize_sql_search(nil) == "%%"
    end

    test "handles empty string" do
      assert StringUtils.normalize_sql_search("") == "%%"
    end

    test "handles cross-field query with diacritics" do
      assert StringUtils.normalize_sql_search("martín v") == "%martin v%"
    end
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ancestry/string_utils_test.exs`
Expected: failures — `normalize(nil)` has no matching clause, `normalize_sql_search/1` undefined

- [ ] **Step 3: Implement**

In `lib/ancestry/string_utils.ex`, add the nil clause before the existing empty-string clause, and add `normalize_sql_search/1`:

```elixir
defmodule Ancestry.StringUtils do
  @doc """
  Strips diacritics and lowercases the string for accent-insensitive comparison.
  """
  def normalize(nil), do: ""
  def normalize(""), do: ""

  def normalize(string) when is_binary(string) do
    string
    |> String.normalize(:nfd)
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
  end

  @doc """
  Normalizes a search term for use in SQL ILIKE queries.
  Strips diacritics, lowercases, escapes SQL wildcards, and wraps in `%...%`.
  """
  def normalize_sql_search(term) do
    escaped =
      term
      |> normalize()
      |> String.replace("\\", "\\\\")
      |> String.replace("%", "\\%")
      |> String.replace("_", "\\_")

    "%#{escaped}%"
  end
end
```

- [ ] **Step 4: Run tests**

Run: `mix test test/ancestry/string_utils_test.exs`
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/string_utils.ex test/ancestry/string_utils_test.exs
git commit -m "Add normalize(nil) clause and normalize_sql_search/1 to StringUtils"
```

---

### Task 2: Migration + Person Schema — name_search column

Add the `name_search` field and compute it in the changeset. Backfill existing rows.

**Files:**
- Create: `priv/repo/migrations/TIMESTAMP_add_name_search_to_persons.exs`
- Modify: `lib/ancestry/people/person.ex`
- Test: `test/ancestry/people/person_kind_test.exs` (extend or create new)

- [ ] **Step 1: Write failing tests for name_search computation**

Add to `test/ancestry/people/person_kind_test.exs` (or create a new file if more appropriate):

```elixir
describe "changeset/2 name_search computation" do
  test "computes name_search from given_name and surname" do
    changeset = Person.changeset(%Person{}, %{given_name: "Martín", surname: "Vazquez"})
    assert get_field(changeset, :name_search) =~ "martin"
    assert get_field(changeset, :name_search) =~ "vazquez"
  end

  test "includes nickname in name_search" do
    changeset = Person.changeset(%Person{}, %{given_name: "Martín", surname: "Vazquez", nickname: "Tincho"})
    assert get_field(changeset, :name_search) =~ "tincho"
  end

  test "includes alternate_names in name_search" do
    changeset = Person.changeset(%Person{}, %{
      given_name: "Martín",
      surname: "Vazquez",
      alternate_names: ["Martín José"]
    })
    assert get_field(changeset, :name_search) =~ "martin jose"
  end

  test "includes birth names in name_search" do
    changeset = Person.changeset(%Person{}, %{
      given_name: "María",
      surname: "López",
      given_name_at_birth: "María",
      surname_at_birth: "García"
    })
    assert get_field(changeset, :name_search) =~ "garcia"
  end

  test "strips diacritics in name_search" do
    changeset = Person.changeset(%Person{}, %{given_name: "Ñoño", surname: "Müller"})
    assert get_field(changeset, :name_search) =~ "nono"
    assert get_field(changeset, :name_search) =~ "muller"
  end

  test "handles all nil name fields" do
    changeset = Person.changeset(%Person{}, %{})
    name_search = get_field(changeset, :name_search)
    assert name_search == "" or is_nil(name_search)
  end

  test "updates name_search when name fields change" do
    person = %Person{given_name: "Old", surname: "Name", name_search: "old name"}
    changeset = Person.changeset(person, %{given_name: "New"})
    assert get_field(changeset, :name_search) =~ "new"
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ancestry/people/person_kind_test.exs`
Expected: failures — `name_search` field doesn't exist

- [ ] **Step 3: Create migration**

Run: `mix ecto.gen.migration add_name_search_to_persons`

Edit the generated file:

```elixir
defmodule Ancestry.Repo.Migrations.AddNameSearchToPersons do
  use Ecto.Migration

  alias Ancestry.Repo
  alias Ancestry.People.Person
  alias Ancestry.StringUtils

  def up do
    alter table(:persons) do
      add :name_search, :text
    end

    flush()

    # Backfill in Elixir to guarantee consistency with changeset logic
    Repo.all(Person)
    |> Enum.each(fn person ->
      name_search = compute_name_search(person)

      Repo.update_all(
        from(p in Person, where: p.id == ^person.id),
        set: [name_search: name_search]
      )
    end)
  end

  def down do
    alter table(:persons) do
      remove :name_search
    end
  end

  defp compute_name_search(person) do
    [
      person.given_name,
      person.surname,
      person.given_name_at_birth,
      person.surname_at_birth,
      person.nickname
    ]
    |> Kernel.++(person.alternate_names || [])
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" ")
    |> StringUtils.normalize()
  end
end
```

Note: `import Ecto.Query` is needed at the top for `from/2`.

- [ ] **Step 4: Update Person schema**

In `lib/ancestry/people/person.ex`:

Add field after `kind` (line 26):
```elixir
field :name_search, :string
```

Add a private function to compute name_search:
```elixir
defp compute_name_search(changeset) do
  fields = [
    get_field(changeset, :given_name),
    get_field(changeset, :surname),
    get_field(changeset, :given_name_at_birth),
    get_field(changeset, :surname_at_birth),
    get_field(changeset, :nickname)
  ]

  alt_names = get_field(changeset, :alternate_names) || []

  name_search =
    (fields ++ alt_names)
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join(" ")
    |> Ancestry.StringUtils.normalize()

  put_change(changeset, :name_search, name_search)
end
```

Call it at the end of `changeset/2`, after `default_birth_names()` (so birth names are populated before computing):

```elixir
def changeset(person, attrs) do
  person
  |> cast(attrs, @cast_fields)
  |> default_birth_names()
  |> compute_name_search()
  |> validate_inclusion(:gender, ~w(female male other))
  |> validate_inclusion(:kind, ~w(family_member acquaintance))
  # ... rest of validations
end
```

**Important:** Do NOT add `:name_search` to `@cast_fields` — it is never user-input.

- [ ] **Step 5: Run migration and tests**

Run: `mix ecto.migrate && mix test test/ancestry/people/person_kind_test.exs`
Expected: all pass

- [ ] **Step 6: Run full test suite**

Run: `mix test`
Expected: all pass

- [ ] **Step 7: Commit**

```bash
git add priv/repo/migrations/*_add_name_search_to_persons.exs lib/ancestry/people/person.ex test/ancestry/people/person_kind_test.exs
git commit -m "Add name_search column to Person, compute in changeset, backfill"
```

---

### Task 3: Search Functions — Switch to name_search

Replace all 6 search functions' multi-field `unaccent()` fragments with `ilike(p.name_search, ^like)`.

**Files:**
- Modify: `lib/ancestry/people.ex:74-96,119-141,247-357`
- Test: `test/ancestry/people_test.exs` (extend)

- [ ] **Step 1: Write failing tests for cross-field search**

Add to `test/ancestry/people_test.exs`:

```elixir
describe "cross-field and diacritics search" do
  setup do
    org = insert(:organization)
    family = insert(:family, organization: org)
    person = insert(:person,
      given_name: "Máximo",
      surname: "Fernández",
      nickname: "Maxi",
      alternate_names: ["Max Fernando"],
      organization: org
    )
    # Force name_search computation by updating through changeset
    {:ok, person} = Ancestry.People.update_person(person, %{})
    insert(:family_member, family: family, person: person)
    %{org: org, family: family, person: person}
  end

  test "search_all_people finds by cross-field query", %{org: org, person: person} do
    results = People.search_all_people("maximo f", org.id)
    ids = Enum.map(results, & &1.id)
    assert person.id in ids
  end

  test "search_all_people finds by diacritics-stripped query", %{org: org, person: person} do
    results = People.search_all_people("maximo", org.id)
    ids = Enum.map(results, & &1.id)
    assert person.id in ids
  end

  test "search_all_people finds by nickname", %{org: org, person: person} do
    results = People.search_all_people("maxi", org.id)
    ids = Enum.map(results, & &1.id)
    assert person.id in ids
  end

  test "search_all_people finds by alternate name", %{org: org, person: person} do
    results = People.search_all_people("fernando", org.id)
    ids = Enum.map(results, & &1.id)
    assert person.id in ids
  end

  test "search_family_members finds by cross-field query", %{family: family, person: person} do
    results = People.search_family_members("maximo f", family.id, 0)
    ids = Enum.map(results, & &1.id)
    assert person.id in ids
  end

  test "list_people_for_family_with_relationship_counts finds by cross-field query", %{family: family, person: person} do
    results = People.list_people_for_family_with_relationship_counts(family.id, "maximo f")
    ids = Enum.map(results, fn {p, _} -> p.id end)
    assert person.id in ids
  end

  test "list_people_for_org finds by cross-field query", %{org: org, person: person} do
    results = People.list_people_for_org(org.id, "maximo f")
    ids = Enum.map(results, fn {p, _} -> p.id end)
    assert person.id in ids
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `mix test test/ancestry/people_test.exs --only "cross-field"`
Expected: FAIL — cross-field queries don't match per-field ILIKE

- [ ] **Step 3: Update all search functions**

In `lib/ancestry/people.ex`, add alias at top:
```elixir
alias Ancestry.StringUtils
```

**Update `list_people_for_family_with_relationship_counts/3`** (line 74-96). Replace the `escaped`/`like` computation and `where` fragment:

```elixir
def list_people_for_family_with_relationship_counts(family_id, search_term, opts) do
  unlinked_only = Keyword.get(opts, :unlinked_only, false)
  acquaintance_only = Keyword.get(opts, :acquaintance_only, false)

  like = StringUtils.normalize_sql_search(search_term)

  base_people_query(family_id)
  |> where([p], ilike(p.name_search, ^like))
  |> maybe_filter_unlinked(unlinked_only)
  |> maybe_filter_acquaintance_only(acquaintance_only)
  |> Repo.all()
end
```

**Update `list_people_for_org/3`** (line 119-141) — same pattern:

```elixir
def list_people_for_org(org_id, search_term, opts) do
  no_family_only = Keyword.get(opts, :no_family_only, false)
  acquaintance_only = Keyword.get(opts, :acquaintance_only, false)

  like = StringUtils.normalize_sql_search(search_term)

  base_org_people_query(org_id)
  |> where([p], ilike(p.name_search, ^like))
  |> maybe_filter_no_family(no_family_only)
  |> maybe_filter_acquaintance_only(acquaintance_only)
  |> Repo.all()
end
```

**Update `search_people/3`** (line 247-275) — replace escaped/like/where block:

```elixir
def search_people(query, exclude_family_id, org_id) do
  like = StringUtils.normalize_sql_search(query)

  Repo.all(
    from p in Person,
      left_join: fm in FamilyMember,
      on: fm.person_id == p.id and fm.family_id == ^exclude_family_id,
      where: is_nil(fm.id),
      where: p.organization_id == ^org_id,
      where: ilike(p.name_search, ^like),
      order_by: [asc: p.surname, asc: p.given_name],
      limit: 20,
      preload: [:families]
  )
end
```

**Update `search_all_people/2`** (line 277-303):

```elixir
def search_all_people(query, org_id) do
  like = StringUtils.normalize_sql_search(query)

  Repo.all(
    from p in Person,
      where: p.organization_id == ^org_id,
      where: p.kind == "family_member",
      where: ilike(p.name_search, ^like),
      order_by: [asc: p.surname, asc: p.given_name],
      limit: 20,
      preload: [:families]
  )
end
```

**Update `search_all_people/3`** (line 305-332):

```elixir
def search_all_people(query, exclude_person_id, org_id) do
  like = StringUtils.normalize_sql_search(query)

  Repo.all(
    from p in Person,
      where: p.id != ^exclude_person_id,
      where: p.organization_id == ^org_id,
      where: p.kind == "family_member",
      where: ilike(p.name_search, ^like),
      order_by: [asc: p.surname, asc: p.given_name],
      limit: 20,
      preload: [:families]
  )
end
```

**Update `search_family_members/3`** (line 334-357):

```elixir
def search_family_members(query, family_id, exclude_person_id) do
  like = StringUtils.normalize_sql_search(query)

  Repo.all(
    from p in Person,
      join: fm in FamilyMember,
      on: fm.person_id == p.id,
      where: fm.family_id == ^family_id,
      where: p.id != ^exclude_person_id,
      where: p.kind == "family_member",
      where: ilike(p.name_search, ^like),
      order_by: [asc: p.surname, asc: p.given_name],
      limit: 20
  )
end
```

- [ ] **Step 4: Run tests**

Run: `mix test`
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add lib/ancestry/people.ex test/ancestry/people_test.exs
git commit -m "Switch all search functions to use name_search column with ilike"
```

---

### Task 4: JS Regex Fix — Unicode support in @mention

Fix the Trix editor regex to accept Unicode characters.

**Files:**
- Modify: `assets/js/trix_editor.js:114`

- [ ] **Step 1: Update the regex**

In `assets/js/trix_editor.js`, line 114, change:

```javascript
const match = text.match(/(?:^|[^a-zA-Z0-9])@([a-zA-Z0-9 ]{0,30})$/)
```

to:

```javascript
const match = text.match(/(?:^|[^\p{L}\p{N}])@([\p{L}\p{N} ]{0,30})$/u)
```

- [ ] **Step 2: Commit**

```bash
git add assets/js/trix_editor.js
git commit -m "Fix @mention regex to accept Unicode characters (diacritics)"
```

---

### Task 5: i18n — Extract new strings

Run gettext extraction in case any new strings were added.

- [ ] **Step 1: Extract**

Run: `mix gettext.extract --merge`

- [ ] **Step 2: Translate any new strings**

Check `priv/gettext/es-UY/LC_MESSAGES/default.po` for untranslated entries and fill them in.

- [ ] **Step 3: Commit** (if changes)

```bash
git add priv/gettext/
git commit -m "Update gettext translations"
```

---

### Task 6: Precommit Check

- [ ] **Step 1: Run precommit**

Run: `mix precommit`

- [ ] **Step 2: Fix any issues**

Address compilation warnings, formatting, or test failures.

- [ ] **Step 3: Final commit if needed**

```bash
git add -A
git commit -m "Fix precommit issues for people search fix"
```
