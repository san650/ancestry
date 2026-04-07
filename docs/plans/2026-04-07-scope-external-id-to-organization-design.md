# Scope Person `external_id` to Organization

## Bug

When importing a CSV into a *new* organization, rows whose external IDs were
previously used by another organization fail with errors like:

```
Row 4: link failed for Adriana: :organization_mismatch
```

**Root cause:** `Ancestry.People.Person` has a globally unique constraint on
`external_id` (`priv/repo/migrations/20260317145427_add_external_id_to_persons.exs`
creates `unique_index(:persons, [:external_id])`), and `Ancestry.Import.CSV`
looks rows up via `Repo.get_by(Person, external_id: …)` with no organization
scoping. When the same source CSV is imported into a second organization, the
import finds the *other* organization's person, then tries to link her to the
target family. `Ancestry.People.add_to_family/2` rejects this with
`:organization_mismatch`, and the row is reported as a row-level failure.

External IDs from third-party sources (FamilyEcho, GEDCOM, etc.) are
tenant-scoped data, not global identifiers. Two unrelated organizations should
be free to import the same source file and end up with their own independent
person rows for the same source ID.

## Fix

Make `external_id` unique per `(organization_id, external_id)` instead of
globally, and scope every CSV import lookup to the target family's organization.

## Schema and migration

**New migration**
`priv/repo/migrations/<timestamp>_scope_person_external_id_to_organization.exs`:

```elixir
defmodule Ancestry.Repo.Migrations.ScopePersonExternalIdToOrganization do
  use Ecto.Migration

  def change do
    drop unique_index(:persons, [:external_id])
    create unique_index(:persons, [:organization_id, :external_id])
  end
end
```

No data transformation is needed: the old constraint was strictly stricter than
the new one, so any row that satisfied the global unique index trivially
satisfies the composite index too. Existing rows are preserved as-is.

NULL `external_id` values: PostgreSQL unique indexes treat NULLs as distinct by
default, so people created via the UI (no `external_id`) remain unaffected —
multiple per organization are still allowed.

**`lib/ancestry/people/person.ex`** — change

```elixir
|> unique_constraint(:external_id)
```

to

```elixir
|> unique_constraint(:external_id, name: :persons_organization_id_external_id_index)
```

We pass the explicit index name (matching what the migration creates) and keep
the field argument as `:external_id` so the changeset error continues to be
attached to the `:external_id` key. If we instead passed
`unique_constraint([:organization_id, :external_id])`, Ecto would auto-derive
the same index name but attribute the error to the **first** field
(`:organization_id`) — which would change `errors_on(changeset).external_id`
from a list to `nil` and break any callers and tests that expect errors on
`:external_id`.

## Import lookup changes

All three `Repo.get_by(Person, external_id: …)` call sites in
`lib/ancestry/import/csv.ex` need to be scoped by `family.organization_id`. Add
a small private helper to keep the call sites readable:

```elixir
defp get_person_by_external_id(org_id, external_id) do
  Repo.get_by(Person, organization_id: org_id, external_id: external_id)
end
```

### `import_or_update_person/4` (line 170)

Replace

```elixir
case Repo.get_by(Person, external_id: attrs.external_id) do
```

with

```elixir
case get_person_by_external_id(family.organization_id, attrs.external_id) do
```

After the fix, importing into a fresh organization no longer finds the
cross-organization person and falls through to the `create_person` branch,
which creates a new organization-scoped person. The `:organization_mismatch`
path becomes unreachable from the import flow but stays in
`link_person_to_family/2` and `add_to_family/2` as defense-in-depth for other
call sites.

### `import_relationships/2` → `import_relationships/3`

The function currently takes only `(adapter_module, rows)` and has no access to
the family or organization. Three places change together:

1. **Function definition** (`lib/ancestry/import/csv.ex` near the existing line
   213): change the head to
   `defp import_relationships(adapter_module, family, rows)`. Inside the
   reduce, replace lines 246–247 with org-scoped lookups:

   ```elixir
   source = get_person_by_external_id(family.organization_id, source_eid)
   target = get_person_by_external_id(family.organization_id, target_eid)
   ```

2. **Caller in `import/4`** (current line 41): change
   `relationships_result = import_relationships(adapter_module, rows)` to
   `relationships_result = import_relationships(adapter_module, family, rows)`.
   The `family` variable is in scope from the preceding
   `find_or_create_family` step.

3. **Caller in `import_for_family/3`** (current line 57): same change. The
   `family` parameter is already passed in.

The `family` reaching `import_relationships/3` is guaranteed to be the same
family used by `import_people/3` in the same import call, so the people pass
and the relationships pass always operate within the same organizational
scope.

No behavior change for the same-organization happy path: re-importing into the
same organization still finds and updates the existing person.

## Tests

### Schema/changeset tests in `test/ancestry/people_test.exs`

A new describe block, `"external_id uniqueness"`:

1. Two persons in the **same organization** with the same `external_id` →
   second insert fails with the composite unique constraint error reported on
   the `:external_id` field.
2. Two persons in **different organizations** with the same `external_id` →
   both succeed.

### Cross-organization import tests in `test/ancestry/import/csv_test.exs`

A new describe block,
`"importing into a fresh organization with previously-used external_ids"`.

**Use `CSV.import_for_family/3` (not `CSV.import/4`) for these tests.**
`Ancestry.Import.CSV.find_or_create_family/2` looks up families by name
without scoping to the passed-in organization, so calling
`CSV.import(adapter, "Smith", path, org_a)` followed by
`CSV.import(adapter, "Smith", path, org_b)` would silently re-use `org_a`'s
"Smith" family on the second call and miss the cross-org behavior we are
testing. That `find_or_create_family/2` lookup is a separate latent bug and is
explicitly out of scope for this design — see "Out of scope" below. By using
`import_for_family/3` with pre-built families in each org, the test routes
around that lookup entirely.

All cross-org test reads of `Person` must be scoped by `organization_id` —
unqualified `Repo.get_by(Person, external_id: …)` becomes ambiguous after the
fix because two rows share the same external ID.

1. **People isolation:**
   - Set up two organizations and a family in each:
     `org_a`/`family_a`, `org_b`/`family_b` (both via the existing factory).
   - Build a CSV with two rows (e.g., `P1` Adriana and `P2` Bruno).
   - `CSV.import_for_family(FamilyEcho, family_a, path)` — assert
     `summary.people_created == 2`.
   - `CSV.import_for_family(FamilyEcho, family_b, path)` — assert
     `summary.people_created == 2`, `summary.people_skipped == 0`,
     `summary.people_added_to_family == 0`, and
     `refute Enum.any?(summary.people_errors, &(&1 =~ "organization_mismatch"))`
     (this assertion explicitly binds the test to the original bug report).
   - Assert each org has its own person row by querying scoped to
     `organization_id`:
     `Repo.get_by!(Person, organization_id: org_a.id, external_id: "family_echo_P1")`
     and
     `Repo.get_by!(Person, organization_id: org_b.id, external_id: "family_echo_P1")`
     return distinct rows with different `id` values.
   - Assert that mutating the `org_b` person (via `People.update_person/2`)
     does not change the `org_a` row.

2. **Relationships isolation:**
   - Same `org_a`/`org_b`/`family_a`/`family_b` setup. CSV includes a
     parent-of relationship and a partner-of relationship.
   - Import into `family_a`, then into `family_b`.
   - For each created relationship in `org_b`, fetch the related persons and
     assert their `organization_id == org_b.id`. This catches the case where
     `import_relationships/3` is wired through but the lookups still return
     `org_a` persons.

### Existing tests preserved

All current tests stay green:

- The same-organization `re-import` tests already exercise the
  `family.organization_id` lookup path correctly, since they re-import into the
  same family within the same organization.
- The new `linking existing people across families` tests added in the previous
  fix (`2026-04-07-csv-import-link-existing-design.md`) use two families
  inside a single shared organization, so the lookup still finds the existing
  person.
- Existing tests that call `Repo.get_by!(Person, external_id: …)` (e.g.,
  `csv_test.exs:259`) keep working unchanged: each of those tests creates only
  a single organization, so there is exactly one row per external ID in their
  sandbox transaction.

## Files changed

- `priv/repo/migrations/<timestamp>_scope_person_external_id_to_organization.exs` — new
- `lib/ancestry/people/person.ex` — `unique_constraint` argument
- `lib/ancestry/import/csv.ex` — three call sites + new private helper +
  `import_relationships/3` signature change + two updated callers
- `test/ancestry/people_test.exs` — new uniqueness describe block
- `test/ancestry/import/csv_test.exs` — new cross-organization describe block

## Out of scope

- Rewriting how `external_id` is generated by adapters (it stays
  `family_echo_<ID>` for the FamilyEcho adapter).
- Backfilling or deduplicating any existing data — there is nothing to
  backfill.
- Removing the `:organization_mismatch` branch from `add_to_family/2` or
  `link_person_to_family/2`. It becomes unreachable from the import flow but
  remains useful as a guard for the public `Ancestry.People` API.
- LiveView modal labels or any other UI — the previous fix
  (`2026-04-07-csv-import-link-existing-design.md`) already covers the
  user-visible state.
- **Fixing `Ancestry.Import.CSV.find_or_create_family/2` to scope its lookup
  by organization.** It currently does
  `Repo.get_by(Family, name: name)` with no `organization_id` filter, which
  means two organizations sharing a family name will collide. This is a real
  bug, but it is independent of the `external_id` collision being fixed here
  and would expand the scope of this change. The cross-org tests in this
  spec route around it by using `import_for_family/3`. A separate spec should
  fix it.
- Concurrent migration safety. `drop unique_index` and `create unique_index`
  both take an `ACCESS EXCLUSIVE` lock by default in PostgreSQL. For the
  current data volume and the existing release-time migration model
  (`fly deploy --remote-only` runs migrations during release), this is fine.
  If this app ever needs zero-downtime migrations on a large `persons` table,
  the migration would need `create_if_not_exists` with `concurrently: true`
  split across two migrations.
