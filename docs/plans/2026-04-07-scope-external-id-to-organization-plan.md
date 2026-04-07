# Scope Person `external_id` to Organization — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `Person.external_id` unique per `(organization_id, external_id)` instead of globally, and scope every CSV import lookup to the target family's organization, so the same source CSV can be imported into different organizations without `:organization_mismatch` errors.

**Architecture:** Two layers change together. (1) Schema layer: a migration swaps the `unique_index` on `persons` and `Person.changeset` is updated to use the new constraint name. (2) Import layer: a small private helper `get_person_by_external_id/2` org-scopes all three `Repo.get_by(Person, external_id: …)` lookups in `lib/ancestry/import/csv.ex`, including the relationships pass which gains a `family` parameter (`import_relationships/2` → `import_relationships/3`).

**Tech Stack:** Elixir, Phoenix, Ecto, PostgreSQL. Tests use `Ancestry.DataCase` (`async: true`) and the existing `Ancestry.Factory` for `insert(:organization)` and `insert(:family, organization: org)`.

**Reference:** `docs/plans/2026-04-07-scope-external-id-to-organization-design.md`

---

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `priv/repo/migrations/<timestamp>_scope_person_external_id_to_organization.exs` | **Create** | Drop the global `unique_index(:persons, [:external_id])` and create `unique_index(:persons, [:organization_id, :external_id])`. |
| `lib/ancestry/people/person.ex` | **Modify** (line 67) | Update `unique_constraint/2` call to use the new composite-index name while keeping the error attached to the `:external_id` field. |
| `lib/ancestry/import/csv.ex` | **Modify** (lines 43, 59, 170, 240, 246–247) | Add a private `get_person_by_external_id/2` helper, scope `import_or_update_person`'s lookup to the family's org, change `import_relationships/2` → `import_relationships/3`, and update both call sites in `import/4` and `import_for_family/3`. |
| `test/ancestry/people_test.exs` | **Modify** | Add a new `describe "external_id uniqueness"` block with two cases: same-org duplicate is rejected, cross-org duplicate is allowed. |
| `test/ancestry/import/csv_test.exs` | **Modify** | Add a new `describe "importing into a fresh organization with previously-used external_ids"` block with two tests: people isolation and relationships isolation. Add `alias Ancestry.People` and `alias Ancestry.Relationships.Relationship` and `import Ecto.Query, only: [from: 2]` if not already imported. |

**Why this decomposition:** The schema layer (migration + changeset + schema tests) is one cohesive commit because the changeset must be updated immediately after running the migration — without it, `Person.changeset` references a stale constraint name and any same-org duplicate insert raises `Ecto.ConstraintError` instead of returning `{:error, changeset}`. The import layer is split into two commits along the natural seam: people lookup (one commit) and relationships lookup (another commit). Each is independently TDD-clean: red test → minimal implementation → green test → commit. Three commits total: schema, import-people, import-relationships.

---

## Task 1: Schema-level fix (migration + changeset + people tests)

**Files:**
- Create: `priv/repo/migrations/<auto-timestamped>_scope_person_external_id_to_organization.exs`
- Modify: `lib/ancestry/people/person.ex:67`
- Test: `test/ancestry/people_test.exs` (new describe block, append at the end of the file before the closing `end`)

### Steps

- [ ] **Step 1: Add the failing schema-level tests**

Edit `test/ancestry/people_test.exs`. Find the last `describe` block in the file (it currently ends near the bottom of the module). Append this new describe block immediately after the last existing `describe` block, before the module's closing `end`:

```elixir
describe "external_id uniqueness" do
  test "rejects duplicate external_id within the same organization" do
    org = insert(:organization)
    family = insert(:family, organization: org)

    assert {:ok, _person} =
             People.create_person(family, %{
               given_name: "Alice",
               surname: "Smith",
               external_id: "ext_1"
             })

    assert {:error, changeset} =
             People.create_person(family, %{
               given_name: "Bob",
               surname: "Smith",
               external_id: "ext_1"
             })

    assert "has already been taken" in errors_on(changeset).external_id
  end

  test "allows the same external_id in different organizations" do
    org_a = insert(:organization)
    org_b = insert(:organization)
    family_a = insert(:family, organization: org_a)
    family_b = insert(:family, organization: org_b)

    assert {:ok, person_a} =
             People.create_person(family_a, %{
               given_name: "Alice",
               surname: "Smith",
               external_id: "ext_1"
             })

    assert {:ok, person_b} =
             People.create_person(family_b, %{
               given_name: "Alice",
               surname: "Smith",
               external_id: "ext_1"
             })

    assert person_a.id != person_b.id
    assert person_a.organization_id == org_a.id
    assert person_b.organization_id == org_b.id
  end
end
```

`People`, `Person`, and the `import Ancestry.Factory` are already aliased/imported at the top of `test/ancestry/people_test.exs`, so no header changes are needed.

- [ ] **Step 2: Run the new tests and confirm they fail**

Run:
```bash
mix test test/ancestry/people_test.exs --only describe:"external_id uniqueness"
```

Expected: the **first** test (same-org duplicate rejected) **already passes** today because the current global `unique_index(:persons, [:external_id])` rejects the second insert and returns a changeset with `"has already been taken"` on `:external_id`. The **second** test (cross-org duplicate allowed) **fails** because the same global constraint also rejects the cross-org insert. The second failure is the meaningful red — proceed to step 3.

- [ ] **Step 3: Generate the migration file**

Run:
```bash
mix ecto.gen.migration scope_person_external_id_to_organization
```

This creates `priv/repo/migrations/<timestamp>_scope_person_external_id_to_organization.exs` with a stub `change/0` body. Note the generated filename — you'll edit it next.

- [ ] **Step 4: Write the migration body**

Edit the file generated in step 3. Replace its contents with:

```elixir
defmodule Ancestry.Repo.Migrations.ScopePersonExternalIdToOrganization do
  use Ecto.Migration

  def change do
    drop unique_index(:persons, [:external_id])
    create unique_index(:persons, [:organization_id, :external_id])
  end
end
```

- [ ] **Step 5: Run the migration on the development database**

Run:
```bash
mix ecto.migrate
```

Expected output mentions `drop index persons_external_id_index` and `create index persons_organization_id_external_id_index`.

- [ ] **Step 6: Update `Person.changeset` to use the new constraint name**

Edit `lib/ancestry/people/person.ex`. On line 67, replace:

```elixir
|> unique_constraint(:external_id)
```

with:

```elixir
|> unique_constraint(:external_id, name: :persons_organization_id_external_id_index)
```

**Why this exact form:** keeping the field argument as `:external_id` (rather than the list `[:organization_id, :external_id]`) tells Ecto to attach the changeset error to `errors_on(changeset).external_id` instead of `errors_on(changeset).organization_id`. The explicit `name:` makes the constraint match the index Ecto autogenerates from `create unique_index(:persons, [:organization_id, :external_id])`.

- [ ] **Step 7: Run the new tests and confirm they pass**

Run:
```bash
mix test test/ancestry/people_test.exs --only describe:"external_id uniqueness"
```

Expected: both tests pass. `mix test` automatically migrates the test database before running, so the new migration is applied without manual intervention.

- [ ] **Step 8: Run the full `people_test.exs` to confirm no regressions in the schema layer**

Run:
```bash
mix test test/ancestry/people_test.exs
```

Expected: all tests pass.

- [ ] **Step 9: Commit**

```bash
git add priv/repo/migrations/*_scope_person_external_id_to_organization.exs lib/ancestry/people/person.ex test/ancestry/people_test.exs
git commit -m "$(cat <<'EOF'
Scope Person external_id uniqueness to organization

Replace the globally-unique index on persons.external_id with a
composite unique index on (organization_id, external_id). Update
Person.changeset to reference the new index name while keeping the
changeset error attached to the :external_id field. External IDs from
third-party sources (FamilyEcho, GEDCOM, etc.) are tenant-scoped and
should not collide across organizations.
EOF
)"
```

---

## Task 2: Import people lookup is org-scoped

**Files:**
- Modify: `lib/ancestry/import/csv.ex` (line 170 and add a private helper)
- Test: `test/ancestry/import/csv_test.exs` (new describe block)

### Steps

- [ ] **Step 1: Add the failing cross-org people-isolation test**

Edit `test/ancestry/import/csv_test.exs`. The file already has these aliases at the top:

```elixir
alias Ancestry.Import.CSV
alias Ancestry.Import.CSV.FamilyEcho
alias Ancestry.People.Person
```

Add one more alias right below them so the new test can call `People.update_person/2`:

```elixir
alias Ancestry.People
```

Then add a new describe block at the end of the module, after the `describe "linking existing people across families"` block and before the private `defp build_csv` helpers near the bottom of the file:

```elixir
describe "importing into a fresh organization with previously-used external_ids" do
  test "people from one org are not reused in another org" do
    org_a = insert(:organization)
    org_b = insert(:organization)
    family_a = insert(:family, organization: org_a)
    family_b = insert(:family, organization: org_b)

    rows = [
      csv_row(%{
        "ID" => "P1",
        "Given names" => "Adriana",
        "Surname now" => "Smith",
        "Gender" => "Female"
      }),
      csv_row(%{
        "ID" => "P2",
        "Given names" => "Bruno",
        "Surname now" => "Smith",
        "Gender" => "Male"
      })
    ]

    path = write_tmp_csv(build_csv(rows))

    assert {:ok, summary_a} = CSV.import_for_family(FamilyEcho, family_a, path)
    assert summary_a.people_created == 2

    assert {:ok, summary_b} = CSV.import_for_family(FamilyEcho, family_b, path)
    assert summary_b.people_created == 2
    assert summary_b.people_skipped == 0
    assert summary_b.people_added_to_family == 0
    refute Enum.any?(summary_b.people_errors, &(&1 =~ "organization_mismatch"))

    person_a =
      Repo.get_by!(Person, organization_id: org_a.id, external_id: "family_echo_P1")

    person_b =
      Repo.get_by!(Person, organization_id: org_b.id, external_id: "family_echo_P1")

    assert person_a.id != person_b.id

    {:ok, _updated} =
      People.update_person(person_b, %{given_name: "Adriana B"})

    refreshed_a = Repo.get!(Person, person_a.id)
    assert refreshed_a.given_name == "Adriana"
  end
end
```

- [ ] **Step 2: Run the new test and confirm it fails**

Run:
```bash
mix test test/ancestry/import/csv_test.exs --only describe:"importing into a fresh organization with previously-used external_ids"
```

Expected: the test fails. Concretely: for each row, the unscoped `Repo.get_by(Person, external_id: …)` finds `org_a`'s person, `import_or_update_person/4` falls into the "existing person, no field changes" branch (incrementing `people_unchanged`), then calls `apply_link_result` which delegates to `link_person_to_family/2`. The link helper sees `person.organization_id != family_b.organization_id`, returns `{:error, :organization_mismatch}`, and the row is counted as `people_skipped` with an error message like `"Row N: link failed for Adriana Smith: :organization_mismatch"`. The `refute Enum.any?(summary_b.people_errors, &(&1 =~ "organization_mismatch"))` assertion catches this.

- [ ] **Step 3: Add the `get_person_by_external_id/2` helper**

Edit `lib/ancestry/import/csv.ex`. Add a new private helper anywhere among the other private functions — placing it right above `defp import_relationships` (around line 240) keeps it next to its first non-people use site. Insert:

```elixir
defp get_person_by_external_id(org_id, external_id) do
  Repo.get_by(Person, organization_id: org_id, external_id: external_id)
end
```

- [ ] **Step 4: Update `import_or_update_person/4` to use the helper**

Still in `lib/ancestry/import/csv.ex`, find line 170:

```elixir
case Repo.get_by(Person, external_id: attrs.external_id) do
```

Replace it with:

```elixir
case get_person_by_external_id(family.organization_id, attrs.external_id) do
```

The `family` variable is already in scope as the first argument of `import_or_update_person/4`.

- [ ] **Step 5: Run the new test and confirm it passes**

Run:
```bash
mix test test/ancestry/import/csv_test.exs --only describe:"importing into a fresh organization with previously-used external_ids"
```

Expected: the test passes.

- [ ] **Step 6: Run the full `csv_test.exs` to confirm no regressions**

Run:
```bash
mix test test/ancestry/import/csv_test.exs
```

Expected: all 15 tests pass (14 existing + 1 new).

- [ ] **Step 7: Commit**

```bash
git add lib/ancestry/import/csv.ex test/ancestry/import/csv_test.exs
git commit -m "$(cat <<'EOF'
Scope CSV import people lookup by organization

Add a private get_person_by_external_id/2 helper and route the
import_or_update_person/4 lookup through it. This makes the people
pass of the import safe across organizations: importing the same
source CSV into a fresh organization no longer finds the other org's
person row and the row is correctly created in the target org.
EOF
)"
```

---

## Task 3: Import relationships lookup is org-scoped

**Files:**
- Modify: `lib/ancestry/import/csv.ex` (lines 43, 59, 240, 246–247)
- Test: `test/ancestry/import/csv_test.exs` (extend the describe block from Task 2)

### Steps

- [ ] **Step 1: Add the failing relationships-isolation test**

Edit `test/ancestry/import/csv_test.exs`. At the top, add one more alias alongside the existing ones:

```elixir
alias Ancestry.Relationships.Relationship
```

`Ecto.Query` is already imported into every `Ancestry.DataCase` test (`test/support/data_case.ex` does `import Ecto.Query`), so the `from p in Person, where: …` syntax in the new test compiles without an extra import.

Inside the same `describe "importing into a fresh organization with previously-used external_ids"` block added in Task 2, append a second test:

```elixir
test "relationships in one org link only that org's people" do
  org_a = insert(:organization)
  org_b = insert(:organization)
  family_a = insert(:family, organization: org_a)
  family_b = insert(:family, organization: org_b)

  rows = [
    csv_row(%{
      "ID" => "DAD",
      "Given names" => "John",
      "Surname now" => "Smith",
      "Gender" => "Male",
      "Partner ID" => "MOM",
      "Partner name" => "Jane Smith"
    }),
    csv_row(%{
      "ID" => "MOM",
      "Given names" => "Jane",
      "Surname now" => "Smith",
      "Gender" => "Female"
    }),
    csv_row(%{
      "ID" => "KID",
      "Given names" => "Billy",
      "Surname now" => "Smith",
      "Gender" => "Male",
      "Mother ID" => "MOM",
      "Mother name" => "Jane Smith",
      "Father ID" => "DAD",
      "Father name" => "John Smith"
    })
  ]

  path = write_tmp_csv(build_csv(rows))

  assert {:ok, _summary_a} = CSV.import_for_family(FamilyEcho, family_a, path)
  assert {:ok, summary_b} = CSV.import_for_family(FamilyEcho, family_b, path)

  assert summary_b.people_created == 3
  assert summary_b.relationships_errors == []

  org_b_person_ids =
    Repo.all(
      from p in Person,
        where: p.organization_id == ^org_b.id,
        select: p.id
    )

  org_b_relationships =
    Repo.all(
      from r in Relationship,
        where: r.person_a_id in ^org_b_person_ids or r.person_b_id in ^org_b_person_ids
    )

  # Every relationship that touches an org_b person should reference
  # only org_b people on BOTH sides — no cross-org leakage.
  for rel <- org_b_relationships do
    assert rel.person_a_id in org_b_person_ids,
           "relationship #{rel.id} (type=#{rel.type}) has person_a from another org"

    assert rel.person_b_id in org_b_person_ids,
           "relationship #{rel.id} (type=#{rel.type}) has person_b from another org"
  end

  # Confirm org_b actually has its own DAD/MOM/KID rows distinct from org_a's.
  dad_a = Repo.get_by!(Person, organization_id: org_a.id, external_id: "family_echo_DAD")
  dad_b = Repo.get_by!(Person, organization_id: org_b.id, external_id: "family_echo_DAD")
  assert dad_a.id != dad_b.id
end
```

- [ ] **Step 2: Run the new test and confirm it fails**

Run:
```bash
mix test test/ancestry/import/csv_test.exs --only describe:"importing into a fresh organization with previously-used external_ids"
```

Expected: the *first* test (people isolation, from Task 2) still passes; the *new* test (relationships isolation) fails — but **not** with a clean assertion failure. After Task 2, two persons share the same external_id (one in `org_a`, one in `org_b`). The unscoped `Repo.get_by(Person, external_id: source_eid)` inside `import_relationships/2` raises `Ecto.MultipleResultsError` the moment it sees the duplicate, so the second `CSV.import_for_family/3` call crashes with a stack trace inside the relationships pass. That crash is the red. Once Task 3's implementation is in place, the lookup is org-scoped and finds exactly one row, the crash goes away, and the `for rel <- org_b_relationships` assertions take over to verify there is no cross-org leakage.

- [ ] **Step 3: Change the `import_relationships/2` signature and scope its lookups**

Edit `lib/ancestry/import/csv.ex`. Find the function head at line 240:

```elixir
defp import_relationships(adapter_module, rows) do
```

Change it to:

```elixir
defp import_relationships(adapter_module, family, rows) do
```

A few lines down, lines 246–247 currently read:

```elixir
source = Repo.get_by(Person, external_id: source_eid)
target = Repo.get_by(Person, external_id: target_eid)
```

Replace them with:

```elixir
source = get_person_by_external_id(family.organization_id, source_eid)
target = get_person_by_external_id(family.organization_id, target_eid)
```

- [ ] **Step 4: Update both callers to pass `family`**

Still in `lib/ancestry/import/csv.ex`, find the two callers of `import_relationships`:

- Line 43, inside `import/4`: change
  ```elixir
  relationships_result = import_relationships(adapter_module, rows)
  ```
  to
  ```elixir
  relationships_result = import_relationships(adapter_module, family, rows)
  ```

- Line 59, inside `import_for_family/3`: same change.

In both cases the `family` variable is already in scope (`import/4` binds it from `find_or_create_family`; `import_for_family/3` receives it as a parameter).

- [ ] **Step 5: Run the relationships test and confirm it passes**

Run:
```bash
mix test test/ancestry/import/csv_test.exs --only describe:"importing into a fresh organization with previously-used external_ids"
```

Expected: both tests in the describe block pass.

- [ ] **Step 6: Run the full `csv_test.exs` to confirm no regressions**

Run:
```bash
mix test test/ancestry/import/csv_test.exs
```

Expected: all 16 tests pass (14 existing + 2 new).

- [ ] **Step 7: Commit**

```bash
git add lib/ancestry/import/csv.ex test/ancestry/import/csv_test.exs
git commit -m "$(cat <<'EOF'
Scope CSV import relationships lookup by organization

Change import_relationships/2 to import_relationships/3 and route its
source/target person lookups through get_person_by_external_id/2 so
they are scoped to the target family's organization. Update both call
sites in import/4 and import_for_family/3 to pass the family. This
closes the last gap — importing the same source CSV into multiple
organizations now produces fully isolated person and relationship
rows in each organization with no cross-org leakage.
EOF
)"
```

---

## Task 4: Final verification

**Files:** none changed.

### Steps

- [ ] **Step 1: Run `mix precommit` and confirm everything passes**

Run:
```bash
mix precommit
```

Expected: compile (warnings as errors) succeeds, formatter is clean, all tests pass. The pre-existing warnings about `~p"/accounts/register"` from `test/web/live/account_live/registration_test.exs` are unrelated to this work and can be ignored.

- [ ] **Step 2: If precommit fails**

- Compile errors: re-read the failing file, fix the issue, re-run.
- Formatter changes: re-stage and amend the appropriate commit. Use `git commit --amend` only on commits that have not been pushed; for already-pushed commits, create a follow-up commit instead.
- Test failures: read the failing assertion, decide whether the test is wrong or the implementation is wrong, fix, re-run.

- [ ] **Step 3: Final sanity check — list the touched files**

Run:
```bash
git log --stat -3
```

Expected: three new commits, touching exactly:
1. **Schema commit:** `priv/repo/migrations/*_scope_person_external_id_to_organization.exs`, `lib/ancestry/people/person.ex`, `test/ancestry/people_test.exs`
2. **Import people commit:** `lib/ancestry/import/csv.ex`, `test/ancestry/import/csv_test.exs`
3. **Import relationships commit:** `lib/ancestry/import/csv.ex`, `test/ancestry/import/csv_test.exs`

No other files should have been changed.

---

## Out of Scope (do not touch)

These are explicitly deferred per the design spec — do not include them in this work even if you notice them:

- `Ancestry.Import.CSV.find_or_create_family/2` is unscoped by org. This is a real latent bug, but it is independent of the `external_id` collision being fixed here. The cross-org tests in this plan route around it by using `import_for_family/3`.
- The `:organization_mismatch` branch in `Ancestry.People.add_to_family/2` and `Ancestry.People.link_person_to_family/2` becomes unreachable from the import flow but stays as defense-in-depth for other call sites of the public `Ancestry.People` API.
- LiveView modal labels — already covered by the previous fix.
- Adapter rewrites and data backfills — neither is needed.
